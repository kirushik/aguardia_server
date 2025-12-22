// use actix_web::{
//     App, Error, HttpMessage, HttpResponse, HttpServer,
//     body::MessageBody,
//     dev::{ServiceRequest, ServiceResponse},
//     middleware::{self, Next},
//     web::{self, Path, Query},
// };
// use actix_files::Files;

mod server;
mod server_0x00;

use actix_cors::Cors;
use actix_web::{
    App, HttpResponse, HttpServer,
    middleware::{self},
    web::{self},
};

mod config;
mod handlers_ws;

// mod ws_engine;
// use crate::ws_engine::*;

mod hub;
use ed25519_dalek::{ VerifyingKey};
use hub::HubState;

use config::CONFIG;
use hex::FromHex;

mod email;
mod postgres;
mod crypto25519;
use crate::crypto25519::*;

use crate::hub::check_heartbeat;

use actix_files::Files;

fn initialize_tracing() {
    use tracing_subscriber::{filter::targets::Targets, prelude::*};

    let level = match CONFIG.loglevel.as_str() {
        "TRACE" => tracing::Level::TRACE, // full
        "DEBUG" => tracing::Level::DEBUG, // for developer
        "INFO" => tracing::Level::INFO,   // normal
        "WARN" => tracing::Level::WARN,   // something went wrong
        "ERROR" => tracing::Level::ERROR, // serious error
        _ => tracing::Level::TRACE,
    };

    tracing_subscriber::registry()
        .with(
            Targets::new()
                .with_target(env!("CARGO_BIN_NAME"), level)
                .with_target("actix", tracing::Level::WARN),
        )
        .with(tracing_subscriber::fmt::layer().compact())
        .init();
}



use std::sync::LazyLock;

pub struct MyConfig {
    pub started_at: std::time::SystemTime,
    pub secret_x: [u8; 32],
    pub public_x: [u8; 32],
    pub secret_ed: [u8; 32],
    pub public_ed: VerifyingKey,
}

pub static MY_CONFIG: LazyLock<MyConfig> = LazyLock::new(|| {
    let seed_x = <[u8; 32]>::from_hex(&CONFIG.seed_x).unwrap();
    let secret_x = x25519_secret(&seed_x);
    let public_x = x25519_public(&secret_x);
    let seed_ed = <[u8; 32]>::from_hex(&CONFIG.seed_ed).unwrap();
    let secret_ed = ed25519_secret(&seed_ed);
    let public_ed = ed25519_public(&secret_ed);
    MyConfig {
        started_at: std::time::SystemTime::now(),
        secret_x,
        public_x,
        secret_ed: secret_ed.as_bytes().clone(),
        public_ed,
    }
});

use sqlx::{postgres::PgPoolOptions, migrate::Migrator};

#[actix_web::main]
async fn main() -> anyhow::Result<()> {
    initialize_tracing();
    tracing::info!("{}/{}", env!("CARGO_BIN_NAME"), env!("CARGO_PKG_VERSION"));

    println!("Starting Aguardia WS server...");
    static MIGRATOR: Migrator = sqlx::migrate!("./migrations");
    let pool = PgPoolOptions::new().max_connections(5).connect(CONFIG.postgres.as_str()).await?;
    if let Err(e) = MIGRATOR.run(&pool).await { panic!("MIGRATE ERROR: {:?}", e); }
    println!("Postgress: ready");

    if CONFIG.seed_x == "" || CONFIG.seed_ed == "" {
        panic!("Crypto seeds are not set! Please set AG_SEED_X and AG_SEED_ED environment variables:
        AG_SEED_X={:?}
        AG_SEED_ED={:?}",
        hex::encode_upper(&crypto25519::seed()),
        hex::encode_upper(&crypto25519::seed())
        );
    }

    // println!("X25519 seed: {}", CONFIG.seed_x);
    // println!("Ed25519 seed: {}", CONFIG.seed_ed);


    // // generate 2 seeds:
    // let seed_x = crypto25519::seed();
    // let seed_ed = crypto25519::seed();
    // println!("Generated new seeds:");
    // println!("  X25519 seed: [{}]", crypto25519::bin_to_base64(&seed_x));
    // println!("  Ed25519 seed: [{}]", crypto25519::bin_to_base64(&seed_ed));
    
    // =============== test data insertion ===============
    // let email     = "lleo2@lleo.me";
    // let info      = "Моя первая запись";
    // let public_x  = b"\x01\x23\x32\x31";   // BYTEA
    // let public_ed = b"\x01\x00\x10";       // BYTEA

    // // let row: (i32,) = sqlx::query_as(r#"
    // //     INSERT INTO users (email, info, public_x, public_ed)
    // //     VALUES ($1, $2, $3, $4)
    // //     RETURNING user_id
    // // "#)
    // // .bind(email)
    // // .bind(info)
    // // .bind(public_x)
    // // .bind(public_ed)
    // // .fetch_one(&postgres)
    // // .await?;
    // // println!("Test data insertion: new user_id = {}", row.0);


    // let rows = postgres::db_json(&postgres, "SELECT * FROM users").await?;
    // println!("Users = {}", rows);


    // =============== test email sending ===============
    // use std::time::{SystemTime, UNIX_EPOCH};
    // let random_id = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    // let subj = format!("Тема тестового письма #{}", random_id);
    // email::send_email(
    //     "no-reply@lleo.me",
    //     "lleo@lleo.me",
    //     &subj,
    //     "<p>Вот твоя красная шапочка: <b>123456</b></p><p><a href=\"https://example.com/reset?code=123456\">Reset Access</a></p>"
    // ).await?;
    // println!("Test email: sent");

    println!("Server listening on {}:{}", CONFIG.bind_host, CONFIG.bind_port);
    println!("WS heartbeat timeout: {} sec", CONFIG.heartbeat_timeout);
    println!("WS ping timeout: {} sec", CONFIG.ping_timeout);
    println!("Email code expired sec: {}", CONFIG.email_code_expired_sec);
    println!("Admins: {:?}", CONFIG.admins);

    // starting HubService
    let hub_state = Arc::new(RwLock::new(HubState::default()));

    // starting heartbeat checker
    check_heartbeat(hub_state.clone());

    let socket = std::net::SocketAddr::new(CONFIG.bind_host.as_str().parse()?, CONFIG.bind_port);

    let url = format!("http://{}:{}", &CONFIG.bind_host, &CONFIG.bind_port);
    tracing::info!("Server running at {}", &url);
    tracing::info!("Log level: {}", &CONFIG.loglevel);
    tracing::info!("API: {}/api", &url);
    tracing::info!(
        "WS: {}/ws",
        format!("ws://{}:{}", &CONFIG.bind_host, &CONFIG.bind_port)
    );
    tracing::info!("Status: {}/status", &url);

    use std::sync::Arc;
    use tokio::sync::RwLock;

    let server = HttpServer::new(move || {
        let cors = Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header()
            .supports_credentials()
            .max_age(3600);

        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(hub_state.clone()))
            .wrap(middleware::Logger::default())
            .wrap(cors)
            .route("/ws/user/v1/{public_ed}", web::get().to(handlers_ws::handler))
            .route("/ws/device/v1/{public_ed}", web::get().to(handlers_ws::handler))
            .route("/status", web::get().to({
                    move |hub_state: web::Data<Arc<RwLock<HubState>>>| {
                        let hub_state = hub_state.clone();
                        async move {
                            let info = {
                              let hub = hub_state.read().await;
                              hub.info_json()
                            };
                            Ok::<_, actix_web::Error>(HttpResponse::Ok().json(info))
                        }
                    }
                }),
            )
            .service(
                Files::new("/", &CONFIG.site_dir)
                .index_file("index.html")
            )
    })
    .bind(socket)?
    .run();

    server.await?;

    Ok(())
}

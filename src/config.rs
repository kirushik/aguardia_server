use std::{path::Path, sync::LazyLock};
use config::FileFormat;
use serde::Deserialize;
// use serde_with::serde_as;
use serde_with::{serde_as, StringWithSeparator};
use serde_with::formats::CommaSeparator;
use crate::hub::UserId;

#[serde_as]
#[derive(Deserialize, Debug)]
pub struct Config {
    // ==== SERVER ====
    pub bind_port: u16,
    pub bind_host: String,
    pub loglevel: String,
    // === WS ===
    pub heartbeat_timeout: u64,
    pub ping_timeout: u64,
    // === MAIL ===
    pub smtp2go_login: String,
    pub smtp2go_password: String,
    pub smtp2go_from: String,
    // === ADMINS ===
    #[serde_as(as = "StringWithSeparator::<CommaSeparator, UserId>")]
    pub admins: Vec<UserId>,
    // === POSTGRESS ===
    pub postgres: String,

    // === site ===
    pub site_dir: String,

    // === crypto seeds ===
    pub seed_x: String,
    pub seed_ed: String,

    pub email_code_expired_sec: u32,
    // pub max_size: Option<usize>,
}

pub static CONFIG: LazyLock<Config> = LazyLock::new(|| {
    const DEFAULTS: &str = std::include_str!("config/default.toml");

    let mut builder =
        config::Config::builder().add_source(config::File::from_str(DEFAULTS, FileFormat::Toml));

    let path = Path::new("etc/config.toml");

    if path.exists() {
        builder = builder.add_source(config::File::with_name(path.as_os_str().to_str().unwrap()));
    }

    let settings = builder
        .add_source(config::Environment::with_prefix("AG"))
        .build()
        .and_then(|c| c.try_deserialize::<Config>());

    match settings {
        Ok(settings) => settings,
        Err(error) => {
            eprintln!("configuration error: {}", error);
            std::process::exit(1);
        }
    }
});

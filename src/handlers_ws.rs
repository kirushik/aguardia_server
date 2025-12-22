use actix_ws;
use ed25519_dalek::{VerifyingKey};
use futures_util::StreamExt;
use futures::future::{AbortHandle, Abortable};
use actix_web::{Error, HttpRequest, HttpResponse, web, error::ErrorBadRequest};
use serde_json::{json};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use hex::FromHex;
use tokio::time::{timeout, Duration};
use crate::{
    MY_CONFIG, config::CONFIG, crypto25519::{self, DecryptError}, email::send_email,
    hub::{self, HubState, UserId, send_to},
    server::server,
};
use sqlx::Row;

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "lowercase", tag = "type")]
pub enum LoginCommand {
    Email {
        email: String,
        signature: String,
    },

    Code {
        code: String,
        x_public: String,
        signature: String,
    },
}


async fn error_close(
    ses: &mut actix_ws::Session,
    msg: &str,
) {
    tracing::warn!("WS error: {:?}", msg);
    let _ = ses.clone().text(json!({"error": msg}).to_string()).await;
    let _ = ses.clone().close(None).await;
}

async fn verify_signature(
    ses: &mut actix_ws::Session,
    payload: &str,
    public_ed: &VerifyingKey,
    signature: &str,
) -> bool {
    let sig_bytes: [u8; 64] = <[u8; 64]>::from_hex(signature).unwrap_or([0; 64]);
    if crypto25519::verify(payload.as_bytes(), &sig_bytes, public_ed) {
        return true;
    }
    error_close(ses, "Signature failed").await;
    false
}

pub async fn handler(
    req: HttpRequest,
    payload: web::Payload,
    hub_state: web::Data<Arc<RwLock<HubState>>>,
    db: web::Data<sqlx::PgPool>,
    path: web::Path<String>,  // <-- kind, public_ed
) -> Result<HttpResponse, Error> {

    let (response, mut session, mut msg_stream) = actix_ws::handle(&req, payload)?;
    let is_user = req.path().starts_with("/ws/user/");
    let public_ed_bytes: [u8; 32] = <[u8; 32]>::from_hex(path.into_inner()).map_err(|_| ErrorBadRequest("Invalid public_ed"))?;
    let public_ed = VerifyingKey::from_bytes(&public_ed_bytes).map_err(|_| ErrorBadRequest("Invalid public_ed"))?;
    let ip = req.peer_addr().map(|addr| addr.ip().to_string()).unwrap_or_default();
    let pool = db.clone(); // &sqlx::PgPool get_ref();
    tracing::debug!("WebSocket connection from {}", ip);

   // === ask BASE for login ===

    let row = sqlx::query_as("SELECT id, public_x FROM users WHERE public_ed = $1")
        .bind(&public_ed_bytes[..])
        .fetch_optional(pool.get_ref())
        .await
        .map_err(|e| {
            tracing::error!("Database error during WS login: {:?}", e);
            ErrorBadRequest("Database error")
        })?;

    if row.is_none() {
        println!("ROW NONE!");

        if !is_user {
            tracing::warn!("Unknown device, close");
            return Err(ErrorBadRequest("Unknown device"));
        }

        let hash = crypto25519::seed();
        let hash = hex::encode_upper(&hash);

        let mut stage = 0;
        let mut mail: String = String::new();
        // let code: String = "332218".to_string(); //  format!("{:06}", rand::random::<u32>() % 1_000_000);
        let mut ses = session.clone();
        let mut ses_timeout = session.clone();

        actix_web::rt::spawn(async move {

            let _ = ses.text(json!({"action": "login", "hash": hash}).to_string()).await;

            let result = timeout(Duration::from_secs(CONFIG.email_code_expired_sec as u64), async {

                let mut code_sent: String = String::new();
                while let Some(Ok(msg)) = msg_stream.next().await {
                    match msg {
                        actix_ws::Message::Ping(bytes) => { ses.pong(&bytes).await.ok(); continue; }
                        actix_ws::Message::Pong(_) => { continue; }
                        actix_ws::Message::Close(reason) => { let _ = ses.close(reason).await; break; }

                        actix_ws::Message::Text(text) => match serde_json::from_str::<LoginCommand>(&text) {
                            Err(_) => {
                                error_close(&mut ses, "Invalid command format").await;
                                break;
                            }
                            Ok(cmd) => {
                                match cmd {
                                    LoginCommand::Email { email, signature } => {

                                        if stage != 0 {
                                            error_close(&mut ses, "Invalid stage").await;
                                            break;
                                        }

                                        if !verify_signature(&mut ses,&format!("{}/email/{}", hash, email), &public_ed, &signature).await {
                                            break;
                                        }

                                        // check mail format
                                        if !email.contains('@')
                                        || !email.contains('.')
                                        || email.len() > 256
                                        || email.len() < 5 {
                                            error_close(&mut ses, "Invalid email format").await;
                                            break;
                                        }

                                        let (code, mail_needs) = {
                                            let mut hub = hub_state.write().await;
                                            hub.get_email_code(&email)
                                        };

                                        code_sent = code.clone();
                                        if !mail_needs {
                                            let _ = ses.text(json!({"action": "code_already_sent", "hash": hash}).to_string()).await;
                                        } else {
                                            mail = email.clone();
                                            if let Err(e) = send_email(
                                                &email,
                                                "Aguardia login code",
                                                &format!("<p>Your login code is: <b>{}</b></p>", code_sent)
                                            ).await {
                                                error_close(&mut ses, &format!("Email error: {:?}", e)).await;
                                                return;
                                            }

                                            let _ = ses.text(json!({"action": "code_sent", "hash": hash}).to_string()).await;
                                        }
                                        stage = 1;
                                        continue;
                                    }

                                    LoginCommand::Code { code: received_code, x_public, signature } => {
                                        if stage != 1 {
                                            let _ = ses.close(None).await;
                                            break;
                                        }
                                        if received_code != code_sent {
                                            error_close(&mut ses, "Invalid code").await;
                                            break;
                                        }
                                        
                                        if !verify_signature(&mut ses,
                                            &format!("{}/code/{}/{}",
                                            hash, received_code, x_public), &public_ed, &signature).await {
                                            break;
                                        }

                                        // save to db with email
                                        let public_x_bytes: [u8; 32] = <[u8; 32]>::from_hex(&x_public).map_err(|_| ErrorBadRequest("Invalid x_public")).unwrap();

                                        let row = sqlx::query(
r"INSERT INTO users (email, public_x, public_ed) VALUES ($1, $2, $3) ON CONFLICT (email)
DO UPDATE SET public_x = EXCLUDED.public_x, public_ed = EXCLUDED.public_ed
RETURNING id"
                                        )
                                        .bind(&mail)
                                        .bind(&public_x_bytes[..])
                                        .bind(&public_ed_bytes[..])
                                        .fetch_one(pool.get_ref())
                                        .await;


                                        let row = match row {
                                            Ok(r) => r,
                                            Err(e) => {
                                                error_close(&mut ses, &format!("DB error: {:?}", e)).await;
                                                break;
                                            }
                                        };

                                        let id: i32 = row.get("id");
                                        let _ = ses.text(json!({
                                            "action": "login_success",
                                            "my_id": id,
                                            "server_X": hex::encode_upper(&MY_CONFIG.public_x),
                                            "server_ed": hex::encode_upper(&MY_CONFIG.public_ed)
                                            }).to_string()).await;
                                        stage = 2;
                                        break;
                                    }
                                }
                            }
                        },

                        _ => {}
                    }
                }
            }).await;

            if result.is_err() {
                error_close(&mut ses_timeout, "Timeout").await;
            }

        });

    // =================================================================================

    } else {

        let (id, public_x): (i32, Vec<u8>) = row.unwrap();
        // public_ed is already known
        let public_x: [u8; 32] = public_x.try_into().unwrap_or([0u8; 32]);
        // let session_id = new_session_id();
        let (abort_handle, abort_reg) = AbortHandle::new_pair();
        let public_ed = VerifyingKey::from_bytes(&public_ed_bytes).unwrap();

        {
            let mut hub = hub_state.write().await;
            hub.add(
                id,
                session.clone(),
                abort_handle,
                ip,
                public_x,
                public_ed,
            );
        }

        tracing::debug!("WebSocket connected: {}", id);

        actix_web::rt::spawn(Abortable::new(async move
        {
            while let Some(Ok(msg)) = msg_stream.next().await {
                // if !matches!(msg, actix_ws::Message::Pong(_)) { tracing::debug!("WebSocket message: {:?}", msg); }

                {
                    let mut hub = hub_state.write().await;
                    hub.renew_heartbeat(id);
                }

                match msg {
                    actix_ws::Message::Ping(bytes) => { session.pong(&bytes).await.ok(); continue; }
                    actix_ws::Message::Pong(_) => { continue; }
                    // actix_ws::Message::Text(text) if text == "ping" => { let _ = session.text("pong").await; continue; }
                    // actix_ws::Message::Text(text) if text == "pong" => { continue; }
                    actix_ws::Message::Close(reason) => {
                        if let Err(e) = session.close(reason).await { tracing::warn!("WS close error: {:?}", e); }
                        break;
                    }
                    // actix_ws::Message::Text(text) if text == "unixtime" => {
                    //     let unixtime = std::time::SystemTime::now()
                    //         .duration_since(std::time::UNIX_EPOCH)
                    //         .unwrap_or_default()
                    //         .as_secs();
                    //     let _ = session.text(unixtime.to_string()).await; continue;
                    // }

                    // ================================================================================
                    actix_ws::Message::Binary(bytes) => {
                        tracing::info!("New binary message from {} length={}", id, bytes.len());

                        let bytes = bytes.as_ref();

                        if bytes.len() < 5 {
                            tracing::warn!("❌ Packet too short");
                            continue;
                        }

                        // читаем адрес в big-endian
                        let addr: u32 =
                            (bytes[0] as u32) |
                            ((bytes[1] as u32) << 8 ) |
                            ((bytes[2] as u32) << 16) |
                            ((bytes[3] as u32) << 24);

                        // пакет адресату
                        if addr != 0 {
                            let mut out = bytes.to_vec();
                            out[0..4].copy_from_slice(&id.to_le_bytes());
                            if ! send_to(
                                &hub_state,
                                addr as UserId,
                                hub::Outgoing::Binary(out)
                            ).await {
                                tracing::warn!("❌ Failed to route to addr {}", addr);
                                let _ = session.text("Failed to route").await;
                                continue;
                            };
                            tracing::info!("Message routed from {} to {}", id, addr);
                            continue;
                        }

                        // пакет серверу
                        println!("### Message from {} to server {}", id, addr);
                        let encrypted = &bytes[4..];
                        tracing::info!("Binary packet: addr={}, encrypted_len={}",addr,encrypted.len());
                        let bin = match crypto25519::verify_and_decrypt(
                            encrypted,
                            &MY_CONFIG.secret_x,
                            &public_x,
                            &public_ed,
                            5, // 5 seconds timeout
                        ) {
                            Ok(v) if !v.is_empty() => v,

                            Err(DecryptError::BadNonce) => {
                                tracing::warn!("❌ decrypt failed: bad nonce");
                                let _ = session.text(format!("timestamp_error:{}",crypto25519::get_unixtime())).await;
                                continue;
                            }
                            Err(DecryptError::BadSignature) => {
                                tracing::warn!("❌ decrypt/verify failed: bad signature");
                                continue;
                            }
                            Err(DecryptError::BadFormat) => {
                                tracing::warn!("❌ decrypt failed: bad format");
                                continue;
                            }

                            Ok(_) => {
                                tracing::warn!("❌ decrypt failed: empty plaintext");
                                continue;
                            }

                            // _ => {
                            //     tracing::warn!("❌ decrypt/verify failed");
                            //     continue;
                            // }
                        };








                        let message_id: u16 = u16::from_le_bytes([bin[0], bin[1]]);
                        let cmd: u8 = bin[2];
                        // let body = &bin[3..];

                        // ===================
                        let body = server(cmd, id, &bin[3..], pool.get_ref(), &hub_state).await;

                        let cmd = 0x01; // ответ
                        let from = 0u32; // сервер=0

                        // ---
                        let mut inner = Vec::with_capacity(3 + body.len());
                        inner.extend_from_slice(&message_id.to_le_bytes()); // id: u16 LE
                        inner.push(cmd);                            // cmd: u8
                        inner.extend_from_slice(&body);              // тело

                        let encoded = crypto25519::encrypt_and_sign(
                            &inner,
                            &MY_CONFIG.secret_x,
                            &ed25519_dalek::SigningKey::from_bytes(&MY_CONFIG.secret_ed),
                            &public_x,
                        );

                        let mut payload = Vec::with_capacity(4 + encoded.len());
                        payload.extend_from_slice(&from.to_le_bytes()); // u32 LE
                        payload.extend_from_slice(&encoded);

                        // ===================
                        // let reply = "ok";
                        // let _ = session.text(reply).await;
                        let _ = session.binary(payload).await;
                        continue;
                    }
// ================================================================================

                    _ => {
                        tracing::warn!("Unknown message: {:?}", msg);
                    }
                }
            }

            {
               let mut hub = hub_state.write().await;
               hub.del(id);
            }
            tracing::debug!("WebSocket disconnected by client: {}", id);
        }, abort_reg ));
    }
    Ok(response)
}

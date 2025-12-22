use serde_json::Value;
use serde_json::json;
use sqlx::PgPool;


use std::sync::Arc;
use tokio::sync::RwLock;
use crate::hub::HubState;

// use crate::hub;
// use sqlx::Row;

fn err(s: &str) -> Vec<u8> {
    serde_json::to_vec(&json!({ "error": s })).unwrap()
}

// fn ok(v: serde_json::Value) -> Vec<u8> {
//     serde_json::to_vec(&v).unwrap()
// }

fn ok1(v: serde_json::Value) -> Vec<u8> {
    let wrapped = serde_json::json!({ "result": v });
    serde_json::to_vec(&wrapped).unwrap()
}

pub async fn server(cmd: u8, user_id: i32, body: &[u8], pool: &PgPool, hub_state: &Arc<RwLock<HubState>>) -> Vec<u8> {

    if cmd == 0x00 {

        let text = std::str::from_utf8(body).unwrap_or("");
        tracing::debug!("✔ 0x00 [{}]", text);

        return match crate::server_0x00::server_0x00(user_id, text, pool, hub_state).await {
            Ok(v) => serde_json::to_vec(&v).unwrap(),
            Err(e) => {
                println!("❌ 0x00 ERROR: {}", e);
                serde_json::to_vec(&json!({ "error": e })).unwrap()
            }
        }

    }

    if cmd == 0x10 {
        let json: Value = match serde_json::from_slice(body) {
            Ok(v) => v,
            Err(_) => return err("Invalid JSON"),
        };
        tracing::debug!("✔ 0x10 json={}", json);

        let time: i64 = json.get("time").and_then(|v| v.as_i64())
        .unwrap_or_else(|| std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs() as i64);

        let result = sqlx::query(
        r#"INSERT INTO data (device_id, time_send, time, payload) VALUES ($1, now(), to_timestamp($2), $3)"#
        )
        .bind(user_id)
        .bind(time)
        .bind(&json)
        .execute(pool)
        .await;
        if let Err(e) = result {
            return err(&format!("db_error: {}", e));
        }
        return ok1(true.into());
    }

    return err("Invalid cmd");

}
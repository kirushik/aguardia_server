use sqlx::PgPool;
use sqlx::Row;
use serde_json::json;
use serde_json::Value;
use hex::FromHex;
use std::sync::Arc;
use tokio::sync::RwLock;
use crate::crypto25519;
use crate::hub::{HubState, UserId, send_to, Outgoing};
use crate::CONFIG;
use crate::MY_CONFIG;

fn get_x_ed(json: &Value) -> Result<([u8;32],[u8;32]), String> {
    Ok((
        <[u8;32]>::from_hex(jstr(json,"x")?).map_err(|_|"bad x".to_string())?,
        <[u8;32]>::from_hex(jstr(json,"ed")?).map_err(|_|"bad ed".to_string())?,
    ))
}

fn get_i32(json: &Value, key: &str) -> Result<UserId, String> {
    json.get(key).and_then(|v| v.as_i64()).map(|v| v as UserId).ok_or(format!("no {}", key))
}

fn get_i64(json: &Value, key: &str) -> Result<i64, String> {
    json.get(key).and_then(|v| v.as_i64()).ok_or(format!("no {}", key))
}

// async fn is_owner_id(json: &Value, pool: &PgPool, user_id: UserId) -> bool {
//     (|| async {
//         let (x, ed) = get_x_ed(&json).ok()?;
//         sqlx::query_scalar::<_, i32>("SELECT 1 FROM users WHERE id = $1 AND public_x = $2 AND public_ed = $3 LIMIT 1")
//             .bind(user_id).bind(x).bind(ed).fetch_optional(pool).await.ok().flatten()?;
//         Some(())
//     })().await.is_some()
// }

// async fn is_owner(json: &Value, pool: &PgPool, device_id: UserId) -> bool {
//     (|| async {
//         let (x, ed) = get_x_ed(&json).ok()?;
//         // let device_id = get_i32(&json, "device_id").ok()?;
//         sqlx::query_scalar::<_, i32>("SELECT 1 FROM users WHERE id = $1 AND public_x = $2 AND public_ed = $3 LIMIT 1")
//             .bind(device_id).bind(x).bind(ed).fetch_optional(pool).await.ok().flatten()?;
//         Some(())
//     })().await.is_some()
// }

// async fn is_owner(json: &Value, pool: &PgPool) -> Result<UserId, &'static str> {
//     let (x, ed) = get_x_ed(json).map_err(|_| "bad x/ed")?;
//     let user_id = get_i32(json, "user_id").map_err(|_| "no user_id")?;
//     let ok = sqlx::query_scalar::<_, i32>("SELECT 1 FROM users WHERE id=$1 AND public_x=$2 AND public_ed=$3 LIMIT 1")
//     .bind(user_id).bind(x).bind(ed).fetch_optional(pool).await.map_err(|_| "db error")?.is_some();
//     if ok { Ok(user_id) } else { Err("not owner") }
// }

async fn is_owner(json: &Value, pool: &PgPool, device_id: UserId) -> Result<(),  &'static str> {
    let (x, ed) = get_x_ed(json).map_err(|_| "bad x/ed")?;
    sqlx::query_scalar::<_, i32>("SELECT 1 FROM users WHERE id=$1 AND public_x=$2 AND public_ed=$3 LIMIT 1")
        .bind(device_id).bind(x).bind(ed).fetch_optional(pool).await
        .map_err(|_| "db error")?
        .ok_or("access denied")?;
    Ok(())
}


fn is_admin(user_id: UserId) -> bool {
    CONFIG.admins.contains(&user_id)
}

fn jstr<'a>(v: &'a Value, key: &str) -> Result<&'a str, String> {
    v.get(key)
        .and_then(|v| v.as_str())
        .ok_or_else(|| format!("Invalid Key '{}'", key))
}

// fn is_key_valid(s: &str) -> bool {
//     if s.len() != 64 { return false; }
//     s.chars().all(|c| c.is_ascii_hexdigit() && (c.is_ascii_digit() || c.is_ascii_uppercase()))
// }

pub async fn server_0x00(user_id: i32, text: &str, pool: &PgPool, hub_state: &Arc<RwLock<HubState>>) -> Result<Value, String> {

    let json: serde_json::Value = serde_json::from_str(text).map_err(|_| "Invalid JSON".to_string())?;

    let action = jstr(&json, "action")?;

    // STATUS
    if action == "status" {
        return Ok(json!(true));
    }

    // MY_ID
    if action == "my_id" {
        return Ok(json!(user_id));
    }

    // MY_ID
    // get_id {"action":"get_id","x":"...","ed":"..."}
    if action == "get_id" {
        let (x, ed) = get_x_ed(&json)?;

        let row = sqlx::query_as::<_, (i32,)>(
            "SELECT id FROM users WHERE public_x = $1 AND public_ed = $2"
        )
        .bind(x)
        .bind(ed)
        .fetch_optional(pool)
        .await.map_err(|e| format!("DB err: {}", e.to_string()))?;

        let out = row.map(|r| json!(r.0)).unwrap_or(json!(false));
        return Ok(out);
    }

    // IS_ONLINE
    // is online {"action":"is_online","x":"...","ed":"..."}
    if action == "is_online" {
        let user_id = get_i32(&json, "user_id")?;
        let (x, ed) = get_x_ed(&json)?;

        let hub = hub_state.read().await;
        let ok = hub.is_online(user_id, &x, &ed);

        return Ok(json!(ok));
    }

    // SEND_TO
    // {"action":"send_to","user_id":1,"x":"...","ed":"...","body":"Hello"}
    if action == "send_to" {
        let user_id = get_i32(&json, "user_id")?;
        let (x, ed) = get_x_ed(&json)?;
        println!("\n\n🔐 Sending to user {}
        x: {:?}
        ed: {:?}
        body \"{}\"", user_id, x, ed, jstr(&json, "body")?);
        {
            let hub = hub_state.read().await;
            if ! hub.is_online(user_id, &x, &ed) {
                return Err("offline".into());
            }
        }
        // ===================
        let body = jstr(&json, "body")?;
        let from = 0u32; // сервер=0
        let mut message_id: u16 = rand::random::<u16>() % 0xFFFF; if message_id == 0 { message_id -= 1; }

        // ---
        let mut inner = Vec::with_capacity(3 + body.len());
        inner.extend_from_slice(&message_id.to_le_bytes()); // id: u16 LE
        inner.push(0x00);                            // cmd: u8
        inner.extend_from_slice(body.as_bytes());              // тело
        let encoded = crypto25519::encrypt_and_sign(
            &inner,
            &MY_CONFIG.secret_x,
            &ed25519_dalek::SigningKey::from_bytes(&MY_CONFIG.secret_ed),
            &x,
        );
        let mut payload = Vec::with_capacity(4 + encoded.len());
        payload.extend_from_slice(&from.to_le_bytes()); // u32 LE
        payload.extend_from_slice(&encoded);
        // ---
        if send_to(
            &hub_state,
            user_id,
            Outgoing::Binary(payload)
        ).await {
            return Ok(json!(true));
        } else {
            return Err("send_error".into());
        };
    }


    // MY_INFO
    // {"action":"my_info"}
    if action == "my_info" {
        let row = sqlx::query(
            r#"
                SELECT info,
                    EXTRACT(EPOCH FROM time_reg)::BIGINT AS time_reg,
                    EXTRACT(EPOCH FROM time_upd)::BIGINT AS time_upd
                FROM users
                WHERE id = $1
            "#
        )
        .bind(user_id)
        .fetch_optional(pool).await.map_err(|e| e.to_string())?.ok_or("user not found")?;

        return Ok(json!({
            "info": row.try_get::<Value, _>("info").unwrap_or(json!(null)),
            "time_reg": row.try_get::<i64, _>("time_reg").map_err(|e| e.to_string())?,
            "time_upd": row.try_get::<i64, _>("time_upd").map_err(|e| e.to_string())?
        }));
    }

    // UPDATE_MY_INFO
    // {"action":"update_my_info","info":{...}}
    if action == "update_my_info" {
        let info = json.get("info").ok_or("no info")?;
        println!("\n\n🔐 Updating user {} info to \"{}\"", user_id, info);
        sqlx::query(r#"UPDATE users SET info = $1 WHERE id = $2"#)
            .bind(info)
            .bind(user_id)
            .execute(pool).await.map_err(|e| format!("DB err: {}", e.to_string()))?;
        return Ok(json!(true));
    }

    // CREATE_NEW_DEVICE
    // {"action":"create_new_device","name":"Device 1", "x":"...","ed":"..."}
    if action == "create_new_device" {
        let name = jstr(&json, "name")?;
        let (x, ed) = get_x_ed(&json)?;
        let info = json!({"name": name});
        let admin_info = json!({ "created_by": user_id, "name": name });

        let result = sqlx::query_as::<_, (i32,)>(
            r#" INSERT INTO users (public_x, public_ed, info, admin_info) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING RETURNING id"#)
        .bind(x)
        .bind(ed)
        .bind(info)
        .bind(admin_info)
        .fetch_optional(pool).await.map_err(|e| format!("DB err: {}", e.to_string()))?;

        let new_id = result.ok_or("already_exists")?.0;
        return Ok(json!(new_id));
    }

    // DELETE_DEVICE (by owner or admin only)
    // admin / user: {"action":"delete_device","device_id":123}
    // device owner: {"action":"delete_device","device_id":123, "x":"...","ed":"..."}
    if action == "delete_device" {
        let device_id = get_i32(&json, "device_id")?;
        if !is_admin(user_id) && device_id != user_id { is_owner(&json, pool, device_id).await?; }
        sqlx::query(r#"DELETE FROM users WHERE id = $1"#)
            .bind(device_id)
            .execute(pool).await.map_err(|e| format!("DB err: {}", e.to_string()))?;
        sqlx::query(r#"DELETE FROM data WHERE device_id = $1"#)
            .bind(device_id)
            .execute(pool).await.map_err(|e| format!("DB err: {}", e.to_string()))?;
        return Ok(json!(true));
    }

    // READ_DATA (by owner or admin only)
    // admin / user: {"action":"read_data","device_id":123, [,"time_from":0,"time_to":9999999999]}
    // device owner: {"action":"read_data","device_id":123, [,"time_from":0,"time_to":9999999999], "x":"...","ed":"..."}
    if action == "read_data" {

        let device_id = get_i32(&json, "device_id")?;
        if !is_admin(user_id) && device_id != user_id { is_owner(&json, pool, device_id).await?; }
        let time_from: i64 = jstr(&json, "time_from")?.parse().unwrap_or(0);
        let time_to: i64 = jstr(&json, "time_to")?.parse().unwrap_or(i64::MAX);

        let rows = sqlx::query(
            r#"
                SELECT id, payload, EXTRACT(EPOCH FROM time)::BIGINT AS time
                FROM data
                WHERE device_id = $1
                AND time BETWEEN to_timestamp($2) AND to_timestamp($3)
                ORDER BY time
                LIMIT 10000
            "#)
        .bind(device_id).bind(time_from).bind(time_to).fetch_all(pool)
        .await.map_err(|e| format!("DB err: {}", e.to_string()))?;
        
        let out: Vec<_> = rows.into_iter().map(|row| json!({
            "id": row.try_get::<i32, _>("id").unwrap(),
            "time": row.try_get::<i64, _>("time").unwrap(),
            "payload": row.try_get::<serde_json::Value, _>("payload").unwrap(),
        })).collect();
        return Ok(json!(out));

    }

    // DELETE_DATA (by owner or admin only)
    // admin / user: {"action":"delete_data","data_id":123, "device_id": 12}
    // device owner: {"action":"delete_data","data_id":123, "device_id": 12, "x":"...","ed":"..."}
    if action == "delete_data" {    
        let data_id = get_i64(&json, "data_id")?;
        let device_id = get_i32(&json, "device_id")?;
        if !is_admin(user_id) && device_id != user_id { is_owner(&json, pool, device_id).await?; }
        sqlx::query(r#"DELETE FROM data WHERE id = $1 AND device_id = $2"#)
            .bind(data_id).bind(device_id).execute(pool).await.map_err(|e| format!("DB err: {}", e.to_string()))?;
        return Ok(json!(true));
    }

    return Err("Not implemented".into());
}
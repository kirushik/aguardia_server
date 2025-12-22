use crate::config::CONFIG;
use crate::MY_CONFIG;

use std::collections::{HashMap};
use std::sync::Arc;
// use std::sync::atomic::{AtomicU64, Ordering};
use ed25519_dalek::VerifyingKey;
use tokio::sync::RwLock;
use serde_json::{Value, json};
// use std::time::Instant;

pub type UserId = i32;

pub struct EmailCode {
    pub code: u32,      // "123456"
    pub expires: std::time::Instant,  // когда протухает
}

#[derive(Default)] // Debug, 
pub struct HubState {
    // основные данные сокета
    sessions: HashMap<UserId, actix_ws::Session>, // WebSocket sessions - чтобы отправлять ему сообщения
    public_x: HashMap<UserId, [u8; 32]>, // его X25519 public key
    public_ed: HashMap<UserId, VerifyingKey>, // его Ed25519 public key
    // излишества сокета
    ip: HashMap<UserId, String>, // его IP адрес нахер не нужен, просто сохранили для информации, ибо где его потом еще взять

    // для обслуживания сокета
    heartbeats: HashMap<UserId, std::time::Instant>, // чтобы проверять жив ли
    serverping: HashMap<UserId, std::time::Instant>, // чтобы его пингать  
    abort_handles: HashMap<UserId, AbortHandle>, // чтобы  его удалить

    // разное другое
    email_codes: HashMap<String, EmailCode>, // высланные ему коды на email
}

use futures::future::AbortHandle;

#[allow(dead_code)]
pub enum Outgoing {
    Text(String),
    Binary(Vec<u8>),
}

impl HubState {

    pub fn is_online(&self, user_id: UserId, x: &[u8;32], ed: &[u8;32]) -> bool {
        self.sessions.contains_key(&user_id)
            && self.public_x.get(&user_id) == Some(x)
            && self.public_ed.get(&user_id).map(|k| k.as_bytes()) == Some(ed)
    }

    pub fn get_email_code(&mut self, email: &str) -> (String, bool) {
        let now = std::time::Instant::now();
        self.email_codes.retain(|_, entry| entry.expires > now);

        match self.email_codes.get(email) {
            Some(entry) => (format!("{:06}", entry.code), false),
            None => {
                let c = rand::random::<u32>() % 1_000_000;
                self.email_codes.insert( email.to_string(),
                 EmailCode {
                        code: c,
                        expires: now + std::time::Duration::from_secs(CONFIG.email_code_expired_sec as u64),
                    },
                );
                (format!("{:06}", c), true)
            }
        }
    }

    pub fn renew_heartbeat(&mut self, id: UserId) {
        if self.sessions.contains_key(&id) {
            let now = std::time::Instant::now();
            self.heartbeats.insert(id, now);
            self.serverping.insert(id, now);
        }
    }

    pub fn add(
        &mut self,
        id: UserId,
        session: actix_ws::Session,
        abort_handle: AbortHandle,
        ip: String,
        public_x: [u8; 32],
        public_ed: VerifyingKey,
    ) {
        self.sessions.insert(id, session);
        self.heartbeats.insert(id, std::time::Instant::now());
        self.serverping.insert(id, std::time::Instant::now());
        self.abort_handles.insert(id, abort_handle);
        self.ip.insert(id, ip);
        self.public_x.insert(id, public_x);
        self.public_ed.insert(id, public_ed);
    }

    pub fn del(&mut self, id: UserId) {
        self.sessions.remove(&id);
        self.heartbeats.remove(&id);
        self.serverping.remove(&id);
        self.abort_handles.remove(&id);
        self.ip.remove(&id);
        self.public_ed.remove(&id);
        self.public_x.remove(&id);

        tracing::debug!("hub.disconnected {}, all: {}", id, self.sessions.len());
    }

    // pub async fn info_users(&self) -> Value {
    //     let users: Vec<String> = self
    //         .name_by_session
    //         .values()
    //         .cloned()
    //         .collect();
    //     json!({
    //         "users": users,
    //         "count": users.len(),
    //     })
    // }

    pub fn info_json(&self) -> Value {
        json!({
            "started_at": MY_CONFIG.started_at.duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0),
            "uptime_minutes": MY_CONFIG.started_at.elapsed().map(|d| d.as_secs() / 60).unwrap_or(0),
            "uptime_days": MY_CONFIG.started_at.elapsed().map(|d| d.as_secs() / 86400).unwrap_or(0),
            "public_x": hex::encode_upper(&MY_CONFIG.public_x),
            "public_ed": hex::encode_upper(&MY_CONFIG.public_ed),
            "loglevel": &CONFIG.loglevel,
            "version": env!("CARGO_PKG_VERSION"),
            "websockets": self.sessions.len(),
            "heartbeats": self.heartbeats.len(),
            "serverping": self.serverping.len(),
            "loops": self.abort_handles.len(),
            "status": "OK",
        })
    }

}


pub fn check_heartbeat(hub_state: Arc<RwLock<HubState>>) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(std::time::Duration::from_secs(2));
        loop {
            ticker.tick().await;

            let now = std::time::Instant::now();
            let timelimit = now - std::time::Duration::from_secs(CONFIG.heartbeat_timeout);
            let pinglimit = now - std::time::Duration::from_secs(CONFIG.ping_timeout);

            let hub = hub_state.read().await;

            let ids_expired: Vec<UserId> = hub
                .heartbeats
                .iter()
                .filter_map(
                    |(&sid, &last)| {
                        if last < timelimit { Some(sid) } else { None }
                    },
                )
                .collect();

            let expired_sessions: Vec<actix_ws::Session> = ids_expired
                .iter()
                .filter_map(|sid| hub.sessions.get(sid).cloned())
                .collect();

            let ids_to_ping: Vec<UserId> = hub
                .serverping
                .iter()
                .filter_map(|(&sid, &last_ping)| {
                    if last_ping < pinglimit {
                        Some(sid)
                    } else {
                        None
                    }
                })
                .collect();
            
            drop(hub);

            for session in &expired_sessions {
                let _ = session.clone().close(None).await;
            }

            if !ids_to_ping.is_empty() || !ids_expired.is_empty() {

                let mut hub = hub_state.write().await;

                for sid in &ids_expired {
                    if let Some(abort_handle) = hub.abort_handles.get(sid) {
                        abort_handle.abort();
                    }
                    tracing::debug!("WebSocket disconnected by timeout: {}", sid);
                    hub.del(*sid);
                }

                for sid in &ids_to_ping {
                    if ids_expired.contains(sid) {
                        continue;
                    }

                    if let Some(session) = hub.sessions.get_mut(sid) {
                        let _ = session.ping(&[]).await;
                    }
                    hub.serverping.insert(*sid, now);
                }

            }
        }
    });
}

// =================================================================

pub async fn send_to(
    hub_state: &Arc<RwLock<HubState>>,
    to: UserId,
    msg: Outgoing,
) -> bool {
    let hub = hub_state.read().await;
    let Some(mut session) = hub.sessions.get(&to).cloned() else {
        return false;
    };
    drop(hub);

    match msg {
        Outgoing::Text(s) => session.text(s).await.is_ok(),
        Outgoing::Binary(b) => session.binary(b).await.is_ok(),
    }
}

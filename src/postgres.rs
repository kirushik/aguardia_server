// use crate::config::CONFIG;

// use sqlx::{postgres::PgPoolOptions, migrate::Migrator, Pool, Postgres, Row, Column};
// use serde_json::{json, Value};

// static MIGRATOR: Migrator = sqlx::migrate!("./migrations");

// pub async fn connect_and_migrate() -> anyhow::Result<sqlx::PgPool> {
//     let pool = PgPoolOptions::new().max_connections(5).connect(CONFIG.postgres.as_str()).await?;
//     if let Err(e) = MIGRATOR.run(&pool).await { panic!("MIGRATE ERROR: {:?}", e); }
//     Ok(pool)
// }

// pub async fn db_json(pool: &sqlx::PgPool, sql: &str) -> anyhow::Result<serde_json::Value> {
//     let wrapped = format!("SELECT json_agg(t) FROM ({}) AS t", sql );
//     let row: (Option<serde_json::Value>,) = sqlx::query_as(&wrapped).fetch_one(pool).await?;
//     Ok(row.0.unwrap_or(serde_json::Value::Array(vec![])))
// }

// pub async fn db(pool: &Pool<Postgres>, sql: &str) -> anyhow::Result<Value> {
//     let rows = sqlx::query(sql).fetch_all(pool).await?;

//     let mut out = Vec::new();

//     for row in rows {
//         let mut obj = serde_json::Map::new();

//         for col in row.columns() {
//             let name = col.name();
//             let val: Result<Value, _> = row.try_get(name);

//             obj.insert(name.to_string(), match val {
//                 Ok(v) => v,
//                 Err(_) => json!(null),
//             });
//         }

//         out.push(Value::Object(obj));
//     }

//     Ok(Value::Array(out))
// }


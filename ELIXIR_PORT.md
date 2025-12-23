# Elixir Porting Guide for Aguardia Server

## Goals
- **Robustness**: Eliminate panic-prone unwrap patterns found in the Rust codebase (e.g., hex decoding, DB unwraps).
- **Scalability**: Remove the global lock contention on heartbeats by leveraging BEAM concurrency (Registry/PubSub).
- **Compatibility**: Preserve protocol, crypto semantics, and routing behaviors exactly.
- **Parity**: Keep operational parity (config, email, DB schema, status endpoint).

## Architecture Outline
- **HTTP/WS layer**: `Bandit` via `Phoenix.Endpoint`
- **Process Model**:
  - **Session Processes**: One process per WebSocket connection. Handles its own heartbeat and state.
  - **Routing Registry**: Use `Registry` (e.g., `Registry.Aguardia`) to map `user_id` -> `pid`. This replaces the central `Hub` lock.
  - **Presence**: Use `Phoenix.Presence` or simple Registry lookups to track online status.
- **Supervision tree**:
  - `Aguardia.Repo` (Ecto).
  - `Aguardia.Web.Endpoint`.
  - `Registry` (for session lookup).
  - `Email` worker/supervisor (for SMTP).
- **Config**: `config/runtime.exs` reading env.
- **Static**: `Plug.Static` serving `CONFIG.site_dir`.

## Protocol & Crypto (Strict Compatibility)
- **Packet framing**:
  - `<<addr::little-32, encrypted::binary>>`
  - If `addr != 0`: Lookup target `pid` via Registry. Rewrite `addr` to `sender_id` (u32 LE) before forwarding.
  - If `addr == 0`: Handle as server command.
- **Crypto Primitives**:
  - X25519 ECDH + XChaCha20-Poly1305.
  - **Nonce Quirk**: Rust derives 24-byte nonce from `u64` time by repeating the LE bytes 3 times. **Must replicate this exactly.**
  - Signature: Ed25519 over `nonce||ciphertext`.
- **Safety**:
  - **Do not crash** on malformed hex or invalid crypto. Return error frames or close socket gracefully.
  - Rust code panics on invalid hex in some paths; Elixir must handle `{:error, _}` tuples.

## Hub Semantics (Distributed)
- **No Central Hub Process**: The Rust version used a global `RwLock` which serialized all heartbeats. In Elixir:
  - **Registration**: On login, the socket process registers itself under `{:via, Registry, {Aguardia.Registry, user_id}}`.
  - **Heartbeat**: Handled internally by the socket process (e.g., `Process.send_after`). No global state update needed.
  - **Routing**: `Registry.lookup` to find the target PID.
  - **Online Check**: `Registry.lookup` returns matches? -> Online.

## Login / Registration Flow
- **Stage 0**: Server sends `{action:"login", hash}`.
- **Client**: `Email { email, signature }`.
  - **Validation**: Improve email validation (regex).
  - **Codes**: Store codes in a dedicated `GenServer` or `ETS` table with TTL.
- **Client**: `Code { code, x_public, signature }`.
  - **Validation**: Verify signature.
  - **DB**: Upsert user. Return `login_success`.

## Control Actions (cmd=0x00, JSON)
- **Compatibility Note**: The Rust implementation expects `time_from`/`time_to` in `read_data` to be **Strings** and parses them. The docs said numbers.
  - **Fix**: The Elixir port should accept **both** Strings and Integers for these fields to ensure maximum compatibility.
- **Actions**:
  - `status`, `my_id`, `get_id`, `is_online`, `send_to`, `my_info`, `update_my_info`.
  - `create_new_device`, `delete_device`, `read_data`, `delete_data`.
- **Authorization**:
  - `delete_device`/`read_data` allow "remote control" if the request includes valid `x` and `ed` keys for the target device, even if not logged in as them. Preserve this logic.

## DB Schema
- Use `Ecto` schemas for `users` and `data`.
- **Tables**:
  - `users`: `id`, `public_x` (binary), `public_ed` (binary), `email`, `admin_info` (map), `info` (map), timestamps.
  - `data`: `id`, `device_id`, `time_send`, `time`, `payload` (map).
- **Telemetry (cmd=0x10)**:
  - Rust accepts any JSON. Use `Ecto.Schema` with a generic `:map` type for `payload` to support schemaless data.

## Config Parity
- **CORS**: Rust allows `*`. Replicate or make configurable.
- **Limits**: Explicitly configure `max_connections` in Cowboy/Bandit to prevent OOM DoS.
- **Env Vars**:
  - `AG_SEED_X`, `AG_SEED_ED` (Required).
  - `AG_POSTGRES`, `AG_BIND_HOST`, `AG_BIND_PORT`.

## Implementation Plan
1.  **Scaffold**: Phoenix/Plug app with no HTML views, just API/WS.
2.  **Crypto Module**: Implement the specific Nonce generation and signing logic. Test against vectors generated from the Rust code.
3.  **Registry**: Set up `Registry` for user routing.
4.  **WebSocket Handler**:
    - Implement the state machine (Unauthenticated -> Authenticated).
    - Handle binary pattern matching for frames.
5.  **Command Handlers**: Implement the JSON actions, ensuring type flexibility (String/Int).
6.  **DB**: Ecto migrations and schemas.

## Test Plan
- **Crypto Vectors**: Generate a valid packet in Rust (hex dump) and ensure Elixir decrypts it.
- **Concurrency**: Spawn 10k processes, ensure heartbeats don't spike CPU (verifying the fix for the global lock issue).
- **Input Fuzzing**: Send malformed hex, short packets, invalid JSON. Ensure the process crashes gracefully (restarts) or handles error without bringing down the VM.
- **Type Coercion**: Test `read_data` with both string timestamps ("123") and integer timestamps (123).

# Aguardia Server - Elixir Port Implementation Plan

## Overview

This document outlines the plan for porting the Aguardia WebSocket server from Rust to Elixir/Phoenix. The port aims to maintain protocol compatibility while leveraging BEAM's concurrency model to eliminate the global lock contention present in the Rust implementation.

## Goals (from ELIXIR_PORT.md)

- **Robustness**: Eliminate panic-prone unwrap patterns
- **Scalability**: Remove global lock contention using Registry/BEAM concurrency
- **Compatibility**: Preserve protocol, crypto semantics, and routing behaviors exactly
- **Parity**: Keep operational parity (config, email, DB schema, status endpoint)

## Architecture

### Project Structure

```
aguardia_elixir/
├── lib/
│   ├── aguardia/
│   │   ├── application.ex          # Supervision tree
│   │   ├── crypto.ex               # All crypto operations (X25519, XChaCha20-Poly1305, Ed25519)
│   │   ├── email_codes.ex          # ETS-based email code storage with TTL
│   │   ├── mailer.ex               # SMTP email sending via Swoosh
│   │   ├── repo.ex                 # Ecto repo
│   │   ├── server_state.ex         # Server keys and startup time
│   │   └── schema/
│   │       ├── user.ex             # User Ecto schema
│   │       └── data.ex             # Telemetry data Ecto schema
│   ├── aguardia_web/
│   │   ├── endpoint.ex             # Phoenix endpoint with Bandit
│   │   ├── router.ex               # HTTP routes
│   │   ├── socket_handler.ex       # WebSock behavior implementation
│   │   ├── commands.ex             # JSON command handlers (cmd=0x00)
│   │   └── controllers/
│   │       └── status_controller.ex
│   └── aguardia.ex                 # Main module
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   ├── runtime.exs                 # Environment variable config
│   └── test.exs
├── priv/
│   └── repo/migrations/
│       └── 20240101000000_create_tables.exs
├── mix.exs
└── mix.lock
```

### Supervision Tree

```
Aguardia.Application
├── Aguardia.Repo (Ecto PostgreSQL)
├── Aguardia.ServerState (Agent for server keys/startup time)
├── Aguardia.EmailCodes (GenServer with ETS for email code storage)
├── Registry (Aguardia.SessionRegistry - :unique keys for user_id -> pid)
└── AguardiaWeb.Endpoint (Phoenix/Bandit HTTP + WebSocket)
```

## Dependencies

```elixir
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:bandit, "~> 1.0"},
    {:websock_adapter, "~> 0.5"},
    {:ecto_sql, "~> 3.10"},
    {:postgrex, "~> 0.17"},
    {:jason, "~> 1.4"},
    {:swoosh, "~> 1.15"},
    {:gen_smtp, "~> 1.2"},
    {:enacl, "~> 1.2"}      # libsodium NIF for XChaCha20-Poly1305, X25519, Ed25519
  ]
end
```

## Protocol Specification

### WebSocket Endpoints

- `GET /ws/user/v1/:public_ed` - User connections (login flow if not registered)
- `GET /ws/device/v1/:public_ed` - Device connections (must be pre-registered)

### Packet Format

All binary WebSocket messages follow this structure:

```
<<addr::little-32, encrypted::binary>>
```

- If `addr != 0`: Route message to user with ID `addr`, rewriting first 4 bytes to sender's ID
- If `addr == 0`: Server command

### Encrypted Payload Format

```
<<nonce::little-64, ciphertext::binary, signature::binary-64>>
```

- **Nonce**: Unix timestamp as u64 little-endian
- **Ciphertext**: XChaCha20-Poly1305 encrypted data
- **Signature**: Ed25519 signature over `nonce || ciphertext`

### Decrypted Message Format

```
<<message_id::little-16, cmd::8, body::binary>>
```

- **message_id**: Client-assigned ID for request/response correlation
- **cmd**: Command type
  - `0x00`: JSON server command
  - `0x01`: Server response
  - `0x10`: Telemetry data

### Nonce Quirk (Critical for Compatibility!)

The 24-byte XChaCha20 nonce is derived from a u64 Unix timestamp by repeating the little-endian bytes 3 times:

```elixir
def nonce_from_u64(timestamp) do
  bytes = <<timestamp::little-64>>
  bytes <> bytes <> bytes  # 24 bytes total
end
```

## Crypto Module Design

### Key Generation

```elixir
# X25519 secret key from seed (clamping)
def x25519_secret(seed) do
  <<first, rest::binary-30, last>> = seed
  first = Bitwise.band(first, 248)
  last = last |> Bitwise.band(127) |> Bitwise.bor(64)
  <<first, rest::binary, last>>
end

# X25519 public key
def x25519_public(secret) do
  :enacl.curve25519_scalarmult_base(secret)
end

# Ed25519 keys - use enacl's sign functions
```

### Encryption/Decryption

```elixir
def encrypt_message(their_public, my_secret, plaintext, nonce) do
  shared = :enacl.curve25519_scalarmult(my_secret, their_public)
  nonce_bytes = nonce_from_u64(nonce)
  :enacl.aead_xchacha20poly1305_ietf_encrypt(plaintext, <<>>, nonce_bytes, shared)
end

def decrypt_message(their_public, my_secret, ciphertext, nonce) do
  shared = :enacl.curve25519_scalarmult(my_secret, their_public)
  nonce_bytes = nonce_from_u64(nonce)
  :enacl.aead_xchacha20poly1305_ietf_decrypt(ciphertext, <<>>, nonce_bytes, shared)
end
```

## Login Flow (for /ws/user/v1/:public_ed)

### Stage 0: Server Challenge
Server sends: `{"action":"login","hash":"<random_hex>"}`

### Stage 1: Email Request
Client sends:
```json
{"type":"email","email":"user@example.com","signature":"<hex>"}
```
Signature is over: `{hash}/email/{email}`

Server validates signature, generates/retrieves 6-digit code, sends email.
Server responds: `{"action":"code_sent","hash":"<hash>"}` or `{"action":"code_already_sent","hash":"<hash>"}`

### Stage 2: Code Verification
Client sends:
```json
{"type":"code","code":"123456","x_public":"<hex>","signature":"<hex>"}
```
Signature is over: `{hash}/code/{code}/{x_public}`

Server validates signature and code, upserts user in DB.
Server responds:
```json
{"action":"login_success","my_id":123,"server_X":"<hex>","server_ed":"<hex>"}
```

## JSON Commands (cmd=0x00)

| Action | Description | Auth Required |
|--------|-------------|---------------|
| `status` | Returns `true` | Yes |
| `my_id` | Returns current user ID | Yes |
| `get_id` | Get user ID by x/ed keys | Yes |
| `is_online` | Check if user is online | Yes |
| `send_to` | Send message to user | Yes |
| `my_info` | Get own user info | Yes |
| `update_my_info` | Update own user info | Yes |
| `create_new_device` | Create new device | Yes |
| `delete_device` | Delete device (self or with x/ed proof) | Yes |
| `read_data` | Read telemetry data | Yes |
| `delete_data` | Delete telemetry data | Yes |

### Authorization Note

For `delete_device`, `read_data`, `delete_data`:
- Admin can access any device
- User can access their own device
- Anyone with valid `x` and `ed` keys for target device can access it (remote control)

### Type Flexibility

`time_from` and `time_to` in `read_data` accept both strings and integers for compatibility.

## Session Management

### Registry-Based Routing

```elixir
# On login success, register process
Registry.register(Aguardia.SessionRegistry, user_id, %{x: public_x, ed: public_ed})

# On disconnect, automatic cleanup (process dies)

# Routing a message
case Registry.lookup(Aguardia.SessionRegistry, target_id) do
  [{pid, _meta}] -> send(pid, {:route, sender_id, payload})
  [] -> {:error, :offline}
end

# Check online status
def is_online?(user_id, x, ed) do
  case Registry.lookup(Aguardia.SessionRegistry, user_id) do
    [{_pid, %{x: ^x, ed: ^ed}}] -> true
    _ -> false
  end
end
```

### Heartbeat Handling

Each WebSocket process handles its own heartbeat using `Process.send_after/3`:

```elixir
def handle_info(:heartbeat_check, state) do
  if now() - state.last_activity > @heartbeat_timeout do
    {:stop, :timeout, state}
  else
    if now() - state.last_ping > @ping_interval do
      {:push, {:ping, <<>>}, schedule_heartbeat(state)}
    else
      {:ok, schedule_heartbeat(state)}
    end
  end
end
```

## Email Codes Storage

Use ETS with periodic cleanup:

```elixir
defmodule Aguardia.EmailCodes do
  use GenServer

  def get_or_create(email) do
    GenServer.call(__MODULE__, {:get_or_create, email})
  end

  # Internal: cleanup expired codes every 60 seconds
  # Store: {email, code, expires_at}
end
```

## Database Schema

### Users Table

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  public_x BYTEA NOT NULL UNIQUE,
  public_ed BYTEA NOT NULL UNIQUE,
  email TEXT UNIQUE,
  admin_info JSONB,
  info JSONB,
  time_reg TIMESTAMPTZ DEFAULT now(),
  time_upd TIMESTAMPTZ DEFAULT now()
);
```

### Data Table

```sql
CREATE TABLE data (
  id BIGSERIAL PRIMARY KEY,
  device_id INT NOT NULL REFERENCES users(id),
  time_send TIMESTAMPTZ NOT NULL,
  time TIMESTAMPTZ NOT NULL,
  payload JSONB NOT NULL
);
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AG_SEED_X` | X25519 seed (64 hex chars) | Required |
| `AG_SEED_ED` | Ed25519 seed (64 hex chars) | Required |
| `AG_POSTGRES` | PostgreSQL URL | Required |
| `AG_BIND_HOST` | Bind host | `0.0.0.0` |
| `AG_BIND_PORT` | Bind port | `8112` |
| `AG_LOGLEVEL` | Log level | `INFO` |
| `AG_HEARTBEAT_TIMEOUT` | Heartbeat timeout (sec) | `90` |
| `AG_PING_TIMEOUT` | Ping interval (sec) | `30` |
| `AG_EMAIL_CODE_EXPIRED_SEC` | Email code TTL (sec) | `600` |
| `AG_SMTP2GO_LOGIN` | SMTP login | Required |
| `AG_SMTP2GO_PASSWORD` | SMTP password | Required |
| `AG_SMTP2GO_FROM` | From address | Required |
| `AG_ADMINS` | Admin user IDs (comma-sep) | `""` |
| `AG_SITE_DIR` | Static files directory | `./www` |

## Error Handling

### Key Principles

1. **Never crash on malformed input** - return error responses or close gracefully
2. **Handle all crypto errors** - bad hex, invalid signatures, decryption failures
3. **Log errors appropriately** - don't expose internal details to clients

### Error Response Format

For JSON commands:
```json
{"error": "error message"}
```

For binary protocol errors, close connection or send text frame with error.

## Status Endpoint

`GET /status` returns:

```json
{
  "started_at": 1234567890,
  "uptime_minutes": 123,
  "uptime_days": 5,
  "public_x": "AABBCC...",
  "public_ed": "DDEEFF...",
  "loglevel": "INFO",
  "version": "1.0.0",
  "websockets": 42,
  "status": "OK"
}
```

## Implementation Phases

### Phase 1: Project Setup
- [x] Create mix.exs with dependencies
- [x] Configure Phoenix endpoint with Bandit
- [x] Setup Ecto with PostgreSQL
- [x] Create database migrations

### Phase 2: Core Infrastructure
- [x] Implement Aguardia.Crypto module
- [x] Implement Aguardia.ServerState
- [x] Implement Aguardia.EmailCodes
- [x] Setup Registry for sessions

### Phase 3: WebSocket Handler
- [x] Implement WebSock behavior
- [x] Implement login flow state machine
- [x] Implement authenticated message handling
- [x] Implement message routing

### Phase 4: Commands
- [x] Implement all JSON commands
- [x] Implement telemetry storage (cmd=0x10)
- [x] Implement authorization checks

### Phase 5: Supporting Features
- [x] Implement email sending
- [x] Implement status endpoint
- [x] Static file serving
- [x] CORS configuration

### Phase 6: Testing & Validation
- [ ] Crypto compatibility tests (generate test vectors from Rust)
- [ ] Protocol compliance tests
- [ ] Load testing (10k connections)
- [ ] Input fuzzing

## Test Plan

### Crypto Vectors
Generate encrypted packets from Rust code, verify Elixir can decrypt them and vice versa.

### Concurrency Test
Spawn 10,000 processes with heartbeats, verify CPU doesn't spike (proving no global lock).

### Input Fuzzing
Send malformed hex, short packets, invalid JSON. Ensure graceful handling.

### Type Coercion
Test `read_data` with both string timestamps ("123") and integer timestamps (123).
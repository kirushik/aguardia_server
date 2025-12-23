# Aguardia Server - Elixir Implementation

A secure WebSocket server for encrypted device-to-device communication, ported from Rust to Elixir/Phoenix.

## Features

- **Encrypted WebSocket Connections**: X25519 ECDH key exchange with XChaCha20-Poly1305 encryption
- **Ed25519 Signatures**: All messages are cryptographically signed
- **Email-based Authentication**: User registration with verification codes
- **Device Management**: Create, delete, and query devices
- **Telemetry Storage**: Store and retrieve timestamped device data
- **Message Routing**: Route encrypted messages between connected clients
- **BEAM Concurrency**: No global locks - each WebSocket is an independent process

## Requirements

- Elixir 1.14+
- PostgreSQL 14+
- libsodium (for enacl NIF)

## Installation

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Create and migrate the database:
   ```bash
   mix ecto.setup
   ```

3. Start the server:
   ```bash
   mix phx.server
   ```

Or run in interactive mode:
```bash
iex -S mix phx.server
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AG_SEED_X` | X25519 seed (64 hex chars) | **Required** |
| `AG_SEED_ED` | Ed25519 seed (64 hex chars) | **Required** |
| `AG_POSTGRES` | PostgreSQL connection URL | **Required in prod** |
| `AG_BIND_HOST` | Bind host | `0.0.0.0` |
| `AG_BIND_PORT` | Bind port | `8112` |
| `AG_LOGLEVEL` | Log level (DEBUG, INFO, WARN, ERROR) | `INFO` |
| `AG_HEARTBEAT_TIMEOUT` | Heartbeat timeout (seconds) | `90` |
| `AG_PING_TIMEOUT` | Ping interval (seconds) | `30` |
| `AG_EMAIL_CODE_EXPIRED_SEC` | Email code TTL (seconds) | `600` |
| `AG_ADMINS` | Admin user IDs (comma-separated) | `""` |
| `AG_SMTP2GO_LOGIN` | SMTP username | - |
| `AG_SMTP2GO_PASSWORD` | SMTP password | - |
| `AG_SMTP2GO_FROM` | Email from address | - |
| `AG_SITE_DIR` | Static files directory | `./priv/static` |

### Generating Seeds

If you don't provide seeds, the server will generate random ones on startup (not suitable for production). To generate seeds:

```bash
# Using openssl
openssl rand -hex 32  # For AG_SEED_X
openssl rand -hex 32  # For AG_SEED_ED
```

## API Endpoints

### WebSocket

- `GET /ws/user/v1/:public_ed` - User connections (with login flow)
- `GET /ws/device/v1/:public_ed` - Device connections (must be pre-registered)

### HTTP

- `GET /status` - Server status and statistics

## Protocol

### Packet Format

Binary WebSocket messages:
```
<<addr::little-32, encrypted::binary>>
```

- If `addr != 0`: Route to user with ID `addr`
- If `addr == 0`: Server command

### Encrypted Payload

```
<<nonce::little-64, ciphertext::binary, signature::binary-64>>
```

### Decrypted Message

```
<<message_id::little-16, cmd::8, body::binary>>
```

Commands:
- `0x00`: JSON server command
- `0x01`: Server response
- `0x10`: Telemetry data

### JSON Commands (cmd=0x00)

| Action | Description |
|--------|-------------|
| `status` | Returns `true` |
| `my_id` | Returns current user ID |
| `get_id` | Get user ID by x/ed keys |
| `is_online` | Check if user is online |
| `send_to` | Send message to user |
| `my_info` | Get own user info |
| `update_my_info` | Update own user info |
| `create_new_device` | Create new device |
| `delete_device` | Delete device |
| `read_data` | Read telemetry data |
| `delete_data` | Delete telemetry data |

## Architecture

### Supervision Tree

```
Aguardia.Application
├── Aguardia.Repo (Ecto PostgreSQL)
├── Phoenix.PubSub
├── Registry (Aguardia.SessionRegistry)
├── Aguardia.EmailCodes (ETS-based code storage)
├── Aguardia.ServerState (Server keys)
└── AguardiaWeb.Endpoint (Phoenix/Bandit)
```

### Key Differences from Rust Implementation

1. **No Global Hub Lock**: Each WebSocket is an independent process using `Registry` for routing
2. **Per-Process Heartbeats**: Each process manages its own heartbeat with `Process.send_after/3`
3. **ETS for Email Codes**: Fast concurrent access with automatic TTL cleanup
4. **WebSock Behavior**: Uses the standard `WebSock` behavior with Bandit

## Development

Run tests:
```bash
mix test
```

Format code:
```bash
mix format
```

## Compatibility

This implementation maintains full protocol compatibility with the Rust version, including:

- Nonce derivation (24-byte from u64 by repeating 3 times)
- Signature format (Ed25519 over nonce||ciphertext)
- Message framing
- JSON command structure
- Database schema

## License

See LICENSE file in the project root.
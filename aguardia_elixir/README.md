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
- libsodium 1.0.12+ (system library required by libsalty2 NIF)

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

## Building Standalone Binary

The Elixir implementation can be compiled into a standalone executable using [Burrito](https://github.com/burrito-elixir/burrito). This creates a self-extracting binary that bundles the BEAM runtime, eliminating the need to have Erlang/Elixir installed on the target system.

### Requirements

To build standalone binaries, you need:
- Zig 0.15.2 (install via `asdf`, `mise`, or download from [ziglang.org](https://ziglang.org/download/))
- XZ compression tools (`xz`)
- patchelf (`apt install patchelf` on Debian/Ubuntu)
- curl (for downloading musl-compiled libsodium)

The build process automatically downloads a musl-compiled libsodium from Alpine Linux and bundles it into the binary, so the resulting executable is fully self-contained and does not require libsodium on the target system.

### Building for Linux x64

```bash
# Ensure libsalty2 NIF is compiled
MIX_ENV=prod mix deps.compile libsalty2

# Build the standalone binary
MIX_ENV=prod mix release

# The binary will be created at:
# burrito_out/aguardia_linux_x64
```

The output binary is a single self-contained executable (~16MB) that can be distributed to any Linux x64 system. It includes:
- The BEAM runtime (musl-based)
- All application code
- The libsalty2 NIF
- A musl-compiled libsodium library

### Running the Standalone Binary

```bash
# Make sure it's executable
chmod +x aguardia_linux_x64

# Run with required environment variables
AG_SEED_X="your-64-char-hex-seed" \
AG_SEED_ED="your-64-char-hex-seed" \
AG_POSTGRES="postgres://user:pass@localhost/aguardia" \
./aguardia_linux_x64
```

### First Run Behavior

On the first run, the binary will:
1. Extract the BEAM runtime and application code to a cache directory
2. Start the Aguardia server

Subsequent runs will reuse the extracted payload unless a new version is detected.

### CLI Commands

The standalone binary provides ergonomic commands for database management and server control:

```bash
# Show help (no AG_POSTGRES required)
./aguardia_linux_x64 --help

# Set the database connection URL
export AG_POSTGRES="postgres://user:pass@localhost/aguardia"

# Create the database and run migrations (recommended for first setup)
./aguardia_linux_x64 setup

# Or run them separately:
./aguardia_linux_x64 createdb
./aguardia_linux_x64 migrate

# Check migration status
./aguardia_linux_x64 migration_status

# Rollback last migration (if needed)
./aguardia_linux_x64 rollback

# Rollback multiple migrations
./aguardia_linux_x64 rollback 3

# Drop database (WARNING: destroys all data!)
./aguardia_linux_x64 dropdb

# Run arbitrary Elixir code
./aguardia_linux_x64 eval "IO.puts(:hello)"

# Start the server (default, no command needed)
./aguardia_linux_x64
```

### Available Commands

| Command | Description |
|---------|-------------|
| (none) | Start the server |
| `setup` | Create database and run all migrations |
| `migrate` | Run pending migrations |
| `rollback [N]` | Rollback last N migrations (default: 1) |
| `createdb` | Create the database |
| `dropdb` | Drop the database (destroys all data!) |
| `migration_status` | Show migration status |
| `eval "CODE"` | Execute arbitrary Elixir code |
| `help`, `-h`, `--help` | Show help message |

### Burrito Maintenance Commands

The standalone binary includes built-in Burrito maintenance commands:

```bash
# Show installation directory
./aguardia_linux_x64 maintenance directory

# Uninstall extracted payload (clear cache)
./aguardia_linux_x64 maintenance uninstall

# Show binary metadata
./aguardia_linux_x64 maintenance meta
```

### Building for Other Targets

To add additional targets, modify the `releases/0` function in `mix.exs`:

```elixir
defp releases do
  [
    aguardia: [
      steps: [:assemble, &Burrito.wrap/1],
      burrito: [
        targets: [
          linux_x64: [os: :linux, cpu: :x86_64],
          # Add more targets as needed:
          # macos: [os: :darwin, cpu: :x86_64],
          # macos_silicon: [os: :darwin, cpu: :aarch64],
          # windows: [os: :windows, cpu: :x86_64]
        ]
      ]
    ]
  ]
end
```

Then build a specific target:

```bash
BURRITO_TARGET=linux_x64 MIX_ENV=prod mix release
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

### Running Tests

The project includes comprehensive tests:

```bash
# Run all tests
mix test

# Run specific test categories
mix test test/aguardia/crypto_test.exs      # Crypto compatibility tests
mix test test/aguardia_web/commands_test.exs # Command handler tests
mix test test/aguardia_web/protocol_test.exs # Protocol compliance tests
mix test test/aguardia/fuzzing_test.exs      # Input fuzzing tests
mix test test/aguardia/load_test.exs         # Load/performance tests
mix test test/aguardia/email_codes_test.exs  # Email codes tests

# Run with verbose output
mix test --trace

# Run excluding slow tests
mix test --exclude load
```

Or use the test runner script:
```bash
./run_tests.sh           # Run all tests
./run_tests.sh crypto    # Run only crypto tests
./run_tests.sh quick     # Run quick tests (exclude load)
./run_tests.sh setup     # Setup test database only
```

### Test Categories

| Category | Description |
|----------|-------------|
| `crypto` | Verifies Rust compatibility using test vectors from the original implementation |
| `commands` | Tests all JSON command handlers (cmd=0x00) |
| `protocol` | Validates binary packet format and framing |
| `fuzzing` | Tests robustness against malformed inputs |
| `load` | Concurrent connection and performance tests |
| `email_codes` | ETS-based email code storage tests |

### Format Code

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

## Standalone Binary Deployment

For production deployment without requiring Erlang/Elixir on the target system, see the [Building Standalone Binary](#building-standalone-binary) section above.

The Burrito-wrapped binary is ideal for:
- On-premise deployments where you cannot install Erlang
- Docker-less deployments
- Distribution as a single executable
- CI/CD pipelines that produce portable artifacts

## License

See LICENSE file in the project root.
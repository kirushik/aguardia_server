defmodule Aguardia do
  @moduledoc """
  Aguardia WebSocket Server - Elixir Implementation

  A secure WebSocket server for encrypted device-to-device communication
  using X25519 ECDH key exchange, XChaCha20-Poly1305 encryption, and
  Ed25519 signatures.

  ## Features

  - Encrypted WebSocket connections with authenticated users and devices
  - Email-based user registration with verification codes
  - Device management (create, delete, query)
  - Telemetry data storage and retrieval
  - Message routing between connected clients

  ## Configuration

  The following environment variables configure the server:

  - `AG_SEED_X` - X25519 seed (64 hex characters, required)
  - `AG_SEED_ED` - Ed25519 seed (64 hex characters, required)
  - `AG_POSTGRES` - PostgreSQL connection URL
  - `AG_BIND_HOST` - Host to bind to (default: 0.0.0.0)
  - `AG_BIND_PORT` - Port to listen on (default: 8112)
  - `AG_HEARTBEAT_TIMEOUT` - WebSocket heartbeat timeout in seconds (default: 90)
  - `AG_PING_TIMEOUT` - Ping interval in seconds (default: 30)
  - `AG_EMAIL_CODE_EXPIRED_SEC` - Email code TTL in seconds (default: 600)
  - `AG_ADMINS` - Comma-separated list of admin user IDs
  - `AG_SMTP2GO_LOGIN` - SMTP username
  - `AG_SMTP2GO_PASSWORD` - SMTP password
  - `AG_SMTP2GO_FROM` - Email from address

  ## WebSocket Endpoints

  - `GET /ws/user/v1/:public_ed` - User connections (login flow if not registered)
  - `GET /ws/device/v1/:public_ed` - Device connections (must be pre-registered)

  ## Protocol

  Binary WebSocket messages use the format:
  `<<addr::little-32, encrypted::binary>>`

  Where encrypted contains:
  `<<nonce::little-64, ciphertext::binary, signature::binary-64>>`
  """

  @doc """
  Returns the application version.
  """
  def version do
    Application.spec(:aguardia, :vsn) |> to_string()
  end
end

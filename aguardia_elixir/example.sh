#!/bin/bash
# Example script to run the Aguardia Elixir server

# Generate random seeds if not provided (for development only)
# In production, use fixed seeds stored securely
export AG_SEED_X=${AG_SEED_X:-$(openssl rand -hex 32 | tr '[:lower:]' '[:upper:]')}
export AG_SEED_ED=${AG_SEED_ED:-$(openssl rand -hex 32 | tr '[:lower:]' '[:upper:]')}

# Database configuration
export AG_POSTGRES=${AG_POSTGRES:-"postgres://postgres:postgres@localhost/aguardia_dev"}

# Server configuration
export AG_BIND_HOST=${AG_BIND_HOST:-"0.0.0.0"}
export AG_BIND_PORT=${AG_BIND_PORT:-8112}
export AG_LOGLEVEL=${AG_LOGLEVEL:-"INFO"}

# WebSocket configuration
export AG_HEARTBEAT_TIMEOUT=${AG_HEARTBEAT_TIMEOUT:-90}
export AG_PING_TIMEOUT=${AG_PING_TIMEOUT:-30}

# Email configuration (optional - set these for email functionality)
# export AG_SMTP2GO_LOGIN="your_login"
# export AG_SMTP2GO_PASSWORD="your_password"
# export AG_SMTP2GO_FROM="noreply@example.com"

# Email code expiry
export AG_EMAIL_CODE_EXPIRED_SEC=${AG_EMAIL_CODE_EXPIRED_SEC:-600}

# Admin user IDs (comma-separated)
export AG_ADMINS=${AG_ADMINS:-"1,2"}

# Static files directory
export AG_SITE_DIR=${AG_SITE_DIR:-"./priv/static"}

echo "Starting Aguardia Server (Elixir)"
echo "================================="
echo "Bind: ${AG_BIND_HOST}:${AG_BIND_PORT}"
echo "Database: ${AG_POSTGRES}"
echo "Log Level: ${AG_LOGLEVEL}"
echo "Heartbeat Timeout: ${AG_HEARTBEAT_TIMEOUT}s"
echo "Ping Timeout: ${AG_PING_TIMEOUT}s"
echo "Email Code TTL: ${AG_EMAIL_CODE_EXPIRED_SEC}s"
echo "Admins: ${AG_ADMINS}"
echo ""

# Install dependencies if needed
if [ ! -d "deps" ]; then
    echo "Installing dependencies..."
    mix deps.get
fi

# Create and migrate database
echo "Setting up database..."
mix ecto.create 2>/dev/null || true
mix ecto.migrate

# Start the server
echo ""
echo "Starting server..."
exec mix phx.server

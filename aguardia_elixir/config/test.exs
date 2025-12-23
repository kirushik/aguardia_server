import Config

config :aguardia, Aguardia.Repo,
  username: "postgres",
  password: "qwerty123",
  hostname: "localhost",
  port: 5432,
  database: "aguardia_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :aguardia, AguardiaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "testsecretkeybasefortestingonly1234567890abcdef",
  server: false

config :aguardia,
  seed_x: "481179010AE65F2BC7508430AC270386953AA75930042E22C184B78B41E95747",
  seed_ed: "454B10B610F9A3A99CD577E6D50A9FBABAA8E50E134B250F2695D17CA446F40E",
  heartbeat_timeout: 90,
  ping_timeout: 30,
  email_code_expired_sec: 600,
  admins: [1, 2],
  site_dir: "./priv/static"

config :aguardia, Aguardia.Mailer, adapter: Swoosh.Adapters.Test

# Disable Swoosh API client for test environment
config :swoosh, :api_client, false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

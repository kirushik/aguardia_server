import Config

config :aguardia, Aguardia.Repo,
  username: "postgres",
  password: "qwerty123",
  hostname: "localhost",
  port: 5432,
  database: "aguardia_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :aguardia, AguardiaWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 8112],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  watchers: []

config :aguardia,
  seed_x: "",
  seed_ed: "",
  heartbeat_timeout: 90,
  ping_timeout: 30,
  email_code_expired_sec: 600,
  admins: [],
  site_dir: "./priv/static"

config :aguardia, Aguardia.Mailer,
  relay: "mail.smtp2go.com",
  username: "my_site.com",
  password: "MyPaSsWoRd",
  port: 587,
  tls: :if_available,
  from: "noreply@my_site.com"

config :logger, level: :debug

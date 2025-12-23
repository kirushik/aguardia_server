import Config

# Runtime configuration loaded from environment variables

if config_env() == :prod do
  database_url =
    System.get_env("AG_POSTGRES") ||
      raise """
      environment variable AG_POSTGRES is missing.
      For example: postgres://user:pass@localhost/aguardia
      """

  config :aguardia, Aguardia.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  host = System.get_env("AG_BIND_HOST") || "0.0.0.0"
  port = String.to_integer(System.get_env("AG_BIND_PORT") || "8112")

  config :aguardia, AguardiaWeb.Endpoint,
    http: [
      ip: host |> String.split(".") |> Enum.map(&String.to_integer/1) |> List.to_tuple(),
      port: port
    ],
    server: true
end

# Crypto seeds (required in all environments for operation)
seed_x = System.get_env("AG_SEED_X") || Application.get_env(:aguardia, :seed_x) || ""
seed_ed = System.get_env("AG_SEED_ED") || Application.get_env(:aguardia, :seed_ed) || ""

config :aguardia,
  seed_x: seed_x,
  seed_ed: seed_ed

# Optional configuration with defaults
heartbeat_timeout =
  String.to_integer(System.get_env("AG_HEARTBEAT_TIMEOUT") || "90")

ping_timeout =
  String.to_integer(System.get_env("AG_PING_TIMEOUT") || "30")

email_code_expired_sec =
  String.to_integer(System.get_env("AG_EMAIL_CODE_EXPIRED_SEC") || "600")

admins =
  case System.get_env("AG_ADMINS") do
    nil -> Application.get_env(:aguardia, :admins) || []
    "" -> []
    str -> str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&String.to_integer/1)
  end

site_dir =
  System.get_env("AG_SITE_DIR") || Application.get_env(:aguardia, :site_dir) || "./priv/static"

loglevel =
  case System.get_env("AG_LOGLEVEL") do
    "TRACE" -> :debug
    "DEBUG" -> :debug
    "INFO" -> :info
    "WARN" -> :warning
    "ERROR" -> :error
    _ -> Application.get_env(:logger, :level) || :info
  end

config :aguardia,
  heartbeat_timeout: heartbeat_timeout,
  ping_timeout: ping_timeout,
  email_code_expired_sec: email_code_expired_sec,
  admins: admins,
  site_dir: site_dir

config :logger, level: loglevel

# SMTP configuration
smtp_login = System.get_env("AG_SMTP2GO_LOGIN")
smtp_password = System.get_env("AG_SMTP2GO_PASSWORD")
smtp_from = System.get_env("AG_SMTP2GO_FROM")

if smtp_login && smtp_password && smtp_from do
  config :aguardia, Aguardia.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: "mail.smtp2go.com",
    username: smtp_login,
    password: smtp_password,
    port: 587,
    tls: :if_available,
    from: smtp_from
end

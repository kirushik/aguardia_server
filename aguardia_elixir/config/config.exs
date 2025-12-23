import Config

config :aguardia,
  ecto_repos: [Aguardia.Repo],
  generators: [timestamp_type: :utc_datetime]

config :aguardia, AguardiaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: AguardiaWeb.ErrorJSON], layout: false],
  pubsub_server: Aguardia.PubSub

config :aguardia, Aguardia.Mailer, adapter: Swoosh.Adapters.SMTP

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"

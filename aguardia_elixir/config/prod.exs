import Config

config :aguardia, Aguardia.Repo, pool_size: 10

config :aguardia, AguardiaWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"

config :logger, level: :info

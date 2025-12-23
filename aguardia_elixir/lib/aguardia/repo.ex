defmodule Aguardia.Repo do
  use Ecto.Repo,
    otp_app: :aguardia,
    adapter: Ecto.Adapters.Postgres
end

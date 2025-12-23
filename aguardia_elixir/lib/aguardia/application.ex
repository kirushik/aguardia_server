defmodule Aguardia.Application do
  @moduledoc """
  The Aguardia Application supervision tree.

  Supervises:
  - Ecto Repo
  - PubSub
  - Session Registry
  - Email Codes storage
  - Server State (keys, startup time)
  - Phoenix Endpoint
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Aguardia.Repo,
      {Phoenix.PubSub, name: Aguardia.PubSub},
      {Registry, keys: :unique, name: Aguardia.SessionRegistry},
      Aguardia.EmailCodes,
      Aguardia.ServerState,
      AguardiaWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Aguardia.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AguardiaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

defmodule Aguardia.ServerState do
  @moduledoc """
  Holds server-wide state including cryptographic keys and startup time.

  The server keys are derived from seeds provided via configuration.
  If seeds are not provided, generates new random seeds and logs them
  (useful for development, but seeds should be set in production).
  """
  use Agent

  require Logger

  alias Aguardia.Crypto

  defstruct [
    :started_at,
    :secret_x,
    :public_x,
    :secret_ed,
    :public_ed
  ]

  @type t :: %__MODULE__{
          started_at: DateTime.t(),
          secret_x: binary(),
          public_x: binary(),
          secret_ed: binary(),
          public_ed: binary()
        }

  def start_link(_opts) do
    Agent.start_link(&init_state/0, name: __MODULE__)
  end

  defp init_state do
    seed_x = Application.get_env(:aguardia, :seed_x, "")
    seed_ed = Application.get_env(:aguardia, :seed_ed, "")

    {secret_x, public_x} = init_x25519_keys(seed_x)
    {secret_ed, public_ed} = init_ed25519_keys(seed_ed)

    state = %__MODULE__{
      started_at: DateTime.utc_now(),
      secret_x: secret_x,
      public_x: public_x,
      secret_ed: secret_ed,
      public_ed: public_ed
    }

    Logger.info("Server X25519 public key: #{Crypto.hex_encode(public_x)}")
    Logger.info("Server Ed25519 public key: #{Crypto.hex_encode(public_ed)}")

    state
  end

  defp init_x25519_keys("") do
    Logger.warning("AG_SEED_X not set, generating random seed (not suitable for production!)")
    seed = Crypto.seed()
    Logger.warning("Generated AG_SEED_X=#{Crypto.hex_encode(seed)}")
    secret = Crypto.x25519_secret(seed)
    public = Crypto.x25519_public(secret)
    {secret, public}
  end

  defp init_x25519_keys(hex_seed) do
    case Crypto.hex_decode32(hex_seed) do
      {:ok, seed} ->
        secret = Crypto.x25519_secret(seed)
        public = Crypto.x25519_public(secret)
        {secret, public}

      {:error, _} ->
        raise "Invalid AG_SEED_X: must be 64 hex characters (32 bytes)"
    end
  end

  defp init_ed25519_keys("") do
    Logger.warning("AG_SEED_ED not set, generating random seed (not suitable for production!)")
    seed = Crypto.seed()
    Logger.warning("Generated AG_SEED_ED=#{Crypto.hex_encode(seed)}")
    {secret, public} = Crypto.ed25519_keypair_from_seed(seed)
    {secret, public}
  end

  defp init_ed25519_keys(hex_seed) do
    case Crypto.hex_decode32(hex_seed) do
      {:ok, seed} ->
        {secret, public} = Crypto.ed25519_keypair_from_seed(seed)
        {secret, public}

      {:error, _} ->
        raise "Invalid AG_SEED_ED: must be 64 hex characters (32 bytes)"
    end
  end

  # Public API

  @doc """
  Get the complete server state.
  """
  @spec get() :: t()
  def get do
    Agent.get(__MODULE__, & &1)
  end

  @doc """
  Get server's X25519 secret key.
  """
  @spec secret_x() :: binary()
  def secret_x do
    Agent.get(__MODULE__, & &1.secret_x)
  end

  @doc """
  Get server's X25519 public key.
  """
  @spec public_x() :: binary()
  def public_x do
    Agent.get(__MODULE__, & &1.public_x)
  end

  @doc """
  Get server's Ed25519 secret key (64 bytes).
  """
  @spec secret_ed() :: binary()
  def secret_ed do
    Agent.get(__MODULE__, & &1.secret_ed)
  end

  @doc """
  Get server's Ed25519 public key.
  """
  @spec public_ed() :: binary()
  def public_ed do
    Agent.get(__MODULE__, & &1.public_ed)
  end

  @doc """
  Get server startup time.
  """
  @spec started_at() :: DateTime.t()
  def started_at do
    Agent.get(__MODULE__, & &1.started_at)
  end

  @doc """
  Get uptime in seconds.
  """
  @spec uptime_seconds() :: non_neg_integer()
  def uptime_seconds do
    DateTime.diff(DateTime.utc_now(), started_at())
  end

  @doc """
  Get server info as a map (for status endpoint).
  """
  @spec info() :: map()
  def info do
    state = get()
    uptime_sec = DateTime.diff(DateTime.utc_now(), state.started_at)

    %{
      started_at: DateTime.to_unix(state.started_at),
      uptime_minutes: div(uptime_sec, 60),
      uptime_days: div(uptime_sec, 86400),
      public_x: Crypto.hex_encode(state.public_x),
      public_ed: Crypto.hex_encode(state.public_ed)
    }
  end
end

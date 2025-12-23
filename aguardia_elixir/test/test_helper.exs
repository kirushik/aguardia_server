# Configure the test environment
ExUnit.configure(formatters: [ExUnit.CLIFormatter], exclude: [:skip])

# Start ExUnit
ExUnit.start()

# Start the application (ensures all children start)
{:ok, _} = Application.ensure_all_started(:aguardia)

# Configure Ecto sandbox mode for database tests
Ecto.Adapters.SQL.Sandbox.mode(Aguardia.Repo, :manual)

# Helper module for test utilities
defmodule Aguardia.TestHelpers do
  @moduledoc """
  Helper functions for tests.
  """

  alias Aguardia.Crypto

  @doc """
  Generate a set of test keys (X25519 and Ed25519).
  """
  def generate_keys do
    seed_x = Crypto.seed()
    x_secret = Crypto.x25519_secret(seed_x)
    x_public = Crypto.x25519_public(x_secret)

    seed_ed = Crypto.seed()
    {ed_secret, ed_public} = Crypto.ed25519_keypair_from_seed(seed_ed)

    %{
      x_secret: x_secret,
      x_public: x_public,
      ed_secret: ed_secret,
      ed_public: ed_public
    }
  end

  @doc """
  Encode binary to uppercase hex.
  """
  def to_hex(bin) when is_binary(bin) do
    Base.encode16(bin, case: :upper)
  end
end

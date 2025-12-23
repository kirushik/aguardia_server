defmodule Aguardia.MixProject do
  use Mix.Project

  # Fix for libsodium compilation on modern GCC (Ubuntu 25.10+)
  # strnlen() requires _GNU_SOURCE to be declared in string.h
  @compile_env_cflags System.get_env("CFLAGS", "")
  unless String.contains?(@compile_env_cflags, "_GNU_SOURCE") do
    System.put_env("CFLAGS", "-D_GNU_SOURCE #{@compile_env_cflags}")
  end

  def project do
    [
      app: :aguardia,
      version: "1.0.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Aguardia.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:bandit, "~> 1.0"},
      {:websock_adapter, "~> 0.5"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.17"},
      {:jason, "~> 1.4"},
      {:swoosh, "~> 1.15"},
      {:gen_smtp, "~> 1.2"},
      {:libsodium, "~> 2.0"},
      {:plug_cowboy, "~> 2.7", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end

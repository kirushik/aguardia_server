defmodule Aguardia.MixProject do
  use Mix.Project

  def project do
    [
      app: :aguardia,
      version: "1.0.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases()
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
      {:hackney, "~> 1.9"},
      {:gen_smtp, "~> 1.2"},
      {:libsalty2, "~> 0.3"},
      {:plug_cowboy, "~> 2.7", only: :test},
      {:burrito, "~> 1.0"}
    ]
  end

  defp releases do
    [
      aguardia: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            linux_x64: [
              os: :linux,
              cpu: :x86_64,
              # Skip NIF recompilation - use host-built NIF
              # The standalone binary requires libsodium to be installed on the target system
              skip_nifs: true
            ]
          ],
          # Custom step to copy the libsalty2 NIF into Burrito's build directory
          # This runs in the patch phase, after Burrito sets up the build structure
          extra_steps: [
            patch: [post: [Aguardia.BurritoCopyNIF]]
          ]
        ]
      ]
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

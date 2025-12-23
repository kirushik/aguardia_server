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

  ## Burrito CLI Commands

  When running as a Burrito binary, the following commands are supported:

      # Create database and run migrations (recommended for initial setup)
      ./aguardia_linux_x64 setup

      # Run migrations only
      ./aguardia_linux_x64 migrate

      # Rollback last migration
      ./aguardia_linux_x64 rollback

      # Rollback multiple migrations
      ./aguardia_linux_x64 rollback 3

      # Create the database only
      ./aguardia_linux_x64 createdb

      # Show migration status
      ./aguardia_linux_x64 migration_status

      # Drop database (dangerous!)
      ./aguardia_linux_x64 dropdb

      # Run arbitrary Elixir code
      ./aguardia_linux_x64 eval "IO.puts(:hello)"

      # Start the server (default, no arguments needed)
      ./aguardia_linux_x64

  Note: The AG_POSTGRES environment variable must be set before running these commands.
  """
  use Application

  @impl true
  def start(_type, _args) do
    # Check if we're running a CLI command
    # Burrito passes CLI args through Burrito.Util.Args.argv()
    args = get_cli_args()

    case args do
      ["help" | _] ->
        print_help()
        System.halt(0)

      ["-h" | _] ->
        print_help()
        System.halt(0)

      ["--help" | _] ->
        print_help()
        System.halt(0)

      ["setup" | _] ->
        run_and_halt(fn -> Aguardia.Release.setup() end)

      ["migrate" | _] ->
        run_and_halt(fn -> Aguardia.Release.migrate() end)

      ["rollback"] ->
        run_and_halt(fn -> Aguardia.Release.rollback() end)

      ["rollback", steps | _] ->
        run_and_halt(fn -> Aguardia.Release.rollback(String.to_integer(steps)) end)

      ["createdb" | _] ->
        run_and_halt(fn -> Aguardia.Release.createdb() end)

      ["dropdb" | _] ->
        run_and_halt(fn -> Aguardia.Release.dropdb() end)

      ["migration_status" | _] ->
        run_and_halt(fn -> Aguardia.Release.migration_status() end)

      ["eval", code | _] ->
        run_eval(code)

      # No arguments or unrecognized - start the server
      _ ->
        start_supervisor()
    end
  end

  defp get_cli_args do
    # Try Burrito's arg helper first, fall back to System.argv()
    if Code.ensure_loaded?(Burrito.Util.Args) do
      apply(Burrito.Util.Args, :argv, [])
    else
      System.argv()
    end
  end

  defp print_help do
    IO.puts("""
    Aguardia Server

    Usage: ./aguardia_linux_x64 [command]

    Commands:
      (none)            Start the server
      setup             Create database and run all migrations
      migrate           Run pending migrations
      rollback [N]      Rollback last N migrations (default: 1)
      createdb          Create the database
      dropdb            Drop the database (WARNING: destroys all data!)
      migration_status  Show migration status
      eval "CODE"       Execute arbitrary Elixir code
      help, -h, --help  Show this help message

    Burrito maintenance:
      maintenance uninstall   Remove extracted runtime files
      maintenance directory   Show runtime installation directory
      maintenance meta        Show binary metadata

    Environment variables:
      AG_POSTGRES       PostgreSQL connection URL (required)
                        Example: postgres://user:pass@localhost/aguardia

      AG_BIND_HOST      Host to bind to (default: 0.0.0.0)
      AG_BIND_PORT      Port to bind to (default: 8112)
      AG_SEED_X         X25519 seed (hex, 64 chars) for deterministic keys
      AG_SEED_ED        Ed25519 seed (hex, 64 chars) for deterministic keys
    """)
  end

  defp run_and_halt(fun) do
    try do
      fun.()
      System.halt(0)
    rescue
      e ->
        IO.puts(:stderr, "Error: #{Exception.message(e)}")
        IO.puts(:stderr, Exception.format_stacktrace(__STACKTRACE__))
        System.halt(1)
    end
  end

  defp run_eval(code) do
    try do
      {result, _binding} = Code.eval_string(code)

      case result do
        :ok -> System.halt(0)
        {:ok, _} -> System.halt(0)
        _ -> System.halt(0)
      end
    rescue
      e ->
        IO.puts(:stderr, "Error executing eval: #{Exception.message(e)}")
        IO.puts(:stderr, Exception.format_stacktrace(__STACKTRACE__))
        System.halt(1)
    end
  end

  defp start_supervisor do
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

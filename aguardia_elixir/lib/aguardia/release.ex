defmodule Aguardia.Release do
  @moduledoc """
  Release tasks for database management.

  These tasks can be run from the standalone Burrito binary:

      # Create database and run migrations (recommended for initial setup)
      ./aguardia_linux_x64 setup

      # Run pending migrations only
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

      # Show help
      ./aguardia_linux_x64 --help

  Note: The AG_POSTGRES environment variable must be set before running these commands.

  These tasks only load the minimal dependencies needed (SSL, Ecto, Postgrex)
  """

  @app :aguardia

  @doc """
  Creates the database if it doesn't exist.
  """
  def createdb do
    load_app()

    case Aguardia.Repo.__adapter__().storage_up(Aguardia.Repo.config()) do
      :ok ->
        IO.puts("Database created successfully")

      {:error, :already_up} ->
        IO.puts("Database already exists")

      {:error, reason} ->
        IO.puts("Failed to create database: #{inspect(reason)}")
        System.halt(1)
    end
  end

  @doc """
  Runs all pending migrations.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    IO.puts("Migrations completed successfully")
  end

  @doc """
  Rolls back the last migration.
  Pass a number to roll back multiple migrations.
  """
  def rollback(steps \\ 1) do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, step: steps))
    end

    IO.puts("Rolled back #{steps} migration(s)")
  end

  @doc """
  Creates the database (if needed) and runs all migrations.
  This is the recommended command for initial setup.
  """
  def setup do
    createdb()
    migrate()
    IO.puts("Setup completed successfully")
  end

  @doc """
  Drops the database.
  WARNING: This will delete all data!
  """
  def dropdb do
    load_app()

    case Aguardia.Repo.__adapter__().storage_down(Aguardia.Repo.config()) do
      :ok ->
        IO.puts("Database dropped successfully")

      {:error, :already_down} ->
        IO.puts("Database does not exist")

      {:error, reason} ->
        IO.puts("Failed to drop database: #{inspect(reason)}")
        System.halt(1)
    end
  end

  @doc """
  Shows the current migration status.
  """
  def migration_status do
    load_app()

    for repo <- repos() do
      {:ok, result, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          migrations = Ecto.Migrator.migrations(repo)

          IO.puts("\nMigration status for #{inspect(repo)}:")
          IO.puts(String.duplicate("-", 60))

          if migrations == [] do
            IO.puts("No migrations found")
          else
            Enum.each(migrations, fn {status, version, name} ->
              status_str = if status == :up, do: "[✓]", else: "[ ]"
              IO.puts("#{status_str} #{version} #{name}")
            end)
          end

          migrations
        end)

      result
    end
  end

  # Private helpers

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end

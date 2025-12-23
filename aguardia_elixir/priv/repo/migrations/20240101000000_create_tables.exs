defmodule Aguardia.Repo.Migrations.CreateTables do
  use Ecto.Migration

  def up do
    # Create users table
    create table(:users) do
      add(:public_x, :binary, null: false)
      add(:public_ed, :binary, null: false)
      add(:email, :text)
      add(:admin_info, :map)
      add(:info, :map)
      add(:time_reg, :utc_datetime_usec, default: fragment("NOW()"))
      add(:time_upd, :utc_datetime_usec, default: fragment("NOW()"))
    end

    create(unique_index(:users, [:public_x]))
    create(unique_index(:users, [:public_ed]))
    create(unique_index(:users, [:email]))

    # Create trigger function for updating time_upd
    execute("""
    CREATE OR REPLACE FUNCTION users_set_time_upd()
    RETURNS TRIGGER AS $$
    BEGIN
      NEW.time_upd = NOW();
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    # Create trigger
    execute("""
    CREATE TRIGGER trg_users_time_upd
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION users_set_time_upd();
    """)

    # Create data table
    create table(:data) do
      add(:device_id, references(:users, on_delete: :delete_all), null: false)
      add(:time_send, :utc_datetime_usec, null: false)
      add(:time, :utc_datetime_usec, null: false)
      add(:payload, :map, null: false)
    end

    create(index(:data, [:device_id]))

    # Create descending index on time for efficient queries
    execute("CREATE INDEX data_device_id_time_desc_idx ON data (device_id, time DESC)")
  end

  def down do
    execute("DROP INDEX IF EXISTS data_device_id_time_desc_idx")
    execute("DROP TRIGGER IF EXISTS trg_users_time_upd ON users")
    execute("DROP FUNCTION IF EXISTS users_set_time_upd()")

    drop(table(:data))
    drop(table(:users))
  end
end

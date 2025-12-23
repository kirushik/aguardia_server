defmodule AguardiaWeb.CommandsTest do
  @moduledoc """
  Tests for AguardiaWeb.Commands module.

  Tests all JSON command handlers for the cmd=0x00 protocol.
  """
  use ExUnit.Case, async: false

  alias AguardiaWeb.Commands
  alias Aguardia.Crypto
  alias Aguardia.Schema.{User, Data}
  alias Aguardia.Repo

  # Use the sandbox for database tests
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  # ==============================================================
  # Helper Functions
  # ==============================================================

  defp create_test_user(opts \\ []) do
    seed = Crypto.seed()
    x_secret = Crypto.x25519_secret(seed)
    x_public = Crypto.x25519_public(x_secret)

    ed_seed = Crypto.seed()
    {_ed_secret, ed_public} = Crypto.ed25519_keypair_from_seed(ed_seed)

    email = Keyword.get(opts, :email)
    info = Keyword.get(opts, :info, %{})

    attrs = %{
      public_x: x_public,
      public_ed: ed_public,
      email: email,
      info: info
    }

    {:ok, user} = Repo.insert(User.changeset(%User{}, attrs))
    {user, x_public, ed_public}
  end

  defp to_hex(bin) when is_binary(bin) do
    Base.encode16(bin, case: :upper)
  end

  # ==============================================================
  # Status Command Tests
  # ==============================================================

  describe "status action" do
    test "returns true" do
      json = Jason.encode!(%{action: "status"})
      assert {:ok, true} = Commands.handle(1, json)
    end
  end

  # ==============================================================
  # my_id Command Tests
  # ==============================================================

  describe "my_id action" do
    test "returns the user's ID" do
      json = Jason.encode!(%{action: "my_id"})
      assert {:ok, 42} = Commands.handle(42, json)
    end
  end

  # ==============================================================
  # get_id Command Tests
  # ==============================================================

  describe "get_id action" do
    test "returns user ID when found" do
      {user, x_public, ed_public} = create_test_user()

      json =
        Jason.encode!(%{
          action: "get_id",
          x: to_hex(x_public),
          ed: to_hex(ed_public)
        })

      expected_id = user.id
      assert {:ok, ^expected_id} = Commands.handle(1, json)
    end

    test "returns false when user not found" do
      json =
        Jason.encode!(%{
          action: "get_id",
          x: String.duplicate("00", 32),
          ed: String.duplicate("00", 32)
        })

      assert {:ok, false} = Commands.handle(1, json)
    end

    test "returns error for missing x key" do
      json =
        Jason.encode!(%{
          action: "get_id",
          ed: String.duplicate("00", 32)
        })

      assert {:error, "no x"} = Commands.handle(1, json)
    end

    test "returns error for invalid hex" do
      json =
        Jason.encode!(%{
          action: "get_id",
          x: "GGGG",
          ed: String.duplicate("00", 32)
        })

      assert {:error, "bad x"} = Commands.handle(1, json)
    end
  end

  # ==============================================================
  # is_online Command Tests
  # ==============================================================

  describe "is_online action" do
    test "returns false when user not in registry" do
      {user, x_public, ed_public} = create_test_user()

      json =
        Jason.encode!(%{
          action: "is_online",
          user_id: user.id,
          x: to_hex(x_public),
          ed: to_hex(ed_public)
        })

      assert {:ok, false} = Commands.handle(1, json)
    end

    test "returns true when user is registered with matching keys" do
      {user, x_public, ed_public} = create_test_user()

      # Register user in the registry
      Registry.register(Aguardia.SessionRegistry, user.id, %{x: x_public, ed: ed_public})

      json =
        Jason.encode!(%{
          action: "is_online",
          user_id: user.id,
          x: to_hex(x_public),
          ed: to_hex(ed_public)
        })

      assert {:ok, true} = Commands.handle(1, json)

      # Cleanup
      Registry.unregister(Aguardia.SessionRegistry, user.id)
    end

    test "returns false when keys don't match" do
      {user, x_public, ed_public} = create_test_user()

      # Register with different keys
      Registry.register(Aguardia.SessionRegistry, user.id, %{
        x: :crypto.strong_rand_bytes(32),
        ed: ed_public
      })

      json =
        Jason.encode!(%{
          action: "is_online",
          user_id: user.id,
          x: to_hex(x_public),
          ed: to_hex(ed_public)
        })

      assert {:ok, false} = Commands.handle(1, json)

      # Cleanup
      Registry.unregister(Aguardia.SessionRegistry, user.id)
    end
  end

  # ==============================================================
  # my_info Command Tests
  # ==============================================================

  describe "my_info action" do
    test "returns user info" do
      {user, _x, _ed} = create_test_user(info: %{"name" => "Test User"})

      json = Jason.encode!(%{action: "my_info"})
      {:ok, result} = Commands.handle(user.id, json)

      assert result.info == %{"name" => "Test User"}
      assert is_integer(result.time_reg) or is_nil(result.time_reg)
    end

    test "returns error for non-existent user" do
      json = Jason.encode!(%{action: "my_info"})
      assert {:error, "user not found"} = Commands.handle(999_999, json)
    end
  end

  # ==============================================================
  # update_my_info Command Tests
  # ==============================================================

  describe "update_my_info action" do
    test "updates user info" do
      {user, _x, _ed} = create_test_user()

      json = Jason.encode!(%{action: "update_my_info", info: %{"name" => "Updated"}})
      assert {:ok, true} = Commands.handle(user.id, json)

      # Verify update
      updated = Repo.get(User, user.id)
      assert updated.info == %{"name" => "Updated"}
    end

    test "returns error when no info provided" do
      {user, _x, _ed} = create_test_user()

      json = Jason.encode!(%{action: "update_my_info"})
      assert {:error, "no info"} = Commands.handle(user.id, json)
    end
  end

  # ==============================================================
  # create_new_device Command Tests
  # ==============================================================

  describe "create_new_device action" do
    test "creates a new device" do
      {user, _x, _ed} = create_test_user()

      new_x = Crypto.seed() |> Crypto.x25519_secret() |> Crypto.x25519_public()
      {_sk, new_ed} = Crypto.seed() |> Crypto.ed25519_keypair_from_seed()

      json =
        Jason.encode!(%{
          action: "create_new_device",
          name: "My Device",
          x: to_hex(new_x),
          ed: to_hex(new_ed)
        })

      {:ok, device_id} = Commands.handle(user.id, json)

      assert is_integer(device_id)

      # Verify device was created
      device = Repo.get(User, device_id)
      assert device.public_x == new_x
      assert device.public_ed == new_ed
      assert device.info == %{"name" => "My Device"}
      assert device.admin_info == %{"created_by" => user.id, "name" => "My Device"}
    end

    test "returns error for duplicate keys" do
      {user, x_public, ed_public} = create_test_user()

      json =
        Jason.encode!(%{
          action: "create_new_device",
          name: "Duplicate",
          x: to_hex(x_public),
          ed: to_hex(ed_public)
        })

      assert {:error, "already_exists"} = Commands.handle(user.id, json)
    end
  end

  # ==============================================================
  # delete_device Command Tests
  # ==============================================================

  describe "delete_device action" do
    test "user can delete their own device (same ID)" do
      {user, x_public, ed_public} = create_test_user()

      json =
        Jason.encode!(%{
          action: "delete_device",
          device_id: user.id
        })

      assert {:ok, true} = Commands.handle(user.id, json)

      # Verify deletion
      assert Repo.get(User, user.id) == nil
    end

    test "user can delete device with valid x/ed keys" do
      {user, _x, _ed} = create_test_user()
      {device, device_x, device_ed} = create_test_user()

      json =
        Jason.encode!(%{
          action: "delete_device",
          device_id: device.id,
          x: to_hex(device_x),
          ed: to_hex(device_ed)
        })

      assert {:ok, true} = Commands.handle(user.id, json)

      # Verify deletion
      assert Repo.get(User, device.id) == nil
    end

    test "returns error without valid access" do
      {user, _x, _ed} = create_test_user()
      {device, _device_x, _device_ed} = create_test_user()

      json =
        Jason.encode!(%{
          action: "delete_device",
          device_id: device.id
        })

      assert {:error, "access denied"} = Commands.handle(user.id, json)
    end

    test "admin can delete any device" do
      {device, _x, _ed} = create_test_user()

      # Temporarily set admin
      Application.put_env(:aguardia, :admins, [9999])

      json =
        Jason.encode!(%{
          action: "delete_device",
          device_id: device.id
        })

      assert {:ok, true} = Commands.handle(9999, json)

      # Cleanup
      Application.put_env(:aguardia, :admins, [])
    end
  end

  # ==============================================================
  # read_data Command Tests
  # ==============================================================

  describe "read_data action" do
    test "reads data for own device" do
      {user, _x, _ed} = create_test_user()

      # Insert some test data
      {:ok, _} = Data.insert(user.id, %{"value" => 42})
      {:ok, _} = Data.insert(user.id, %{"value" => 43})

      json =
        Jason.encode!(%{
          action: "read_data",
          device_id: user.id,
          time_from: 0,
          time_to: 9_999_999_999
        })

      {:ok, data} = Commands.handle(user.id, json)

      assert is_list(data)
      assert length(data) == 2
    end

    test "accepts string timestamps" do
      {user, _x, _ed} = create_test_user()
      {:ok, _} = Data.insert(user.id, %{"value" => 1})

      json =
        Jason.encode!(%{
          action: "read_data",
          device_id: user.id,
          time_from: "0",
          time_to: "9999999999"
        })

      {:ok, data} = Commands.handle(user.id, json)
      assert is_list(data)
    end

    test "accepts integer timestamps" do
      {user, _x, _ed} = create_test_user()
      {:ok, _} = Data.insert(user.id, %{"value" => 1})

      json =
        Jason.encode!(%{
          action: "read_data",
          device_id: user.id,
          time_from: 0,
          time_to: 9_999_999_999
        })

      {:ok, data} = Commands.handle(user.id, json)
      assert is_list(data)
    end

    test "returns error without access" do
      {user, _x, _ed} = create_test_user()
      {device, _device_x, _device_ed} = create_test_user()

      json =
        Jason.encode!(%{
          action: "read_data",
          device_id: device.id
        })

      assert {:error, "access denied"} = Commands.handle(user.id, json)
    end
  end

  # ==============================================================
  # delete_data Command Tests
  # ==============================================================

  describe "delete_data action" do
    test "deletes specific data record" do
      {user, _x, _ed} = create_test_user()
      {:ok, data_record} = Data.insert(user.id, %{"value" => 42})

      json =
        Jason.encode!(%{
          action: "delete_data",
          data_id: data_record.id,
          device_id: user.id
        })

      assert {:ok, true} = Commands.handle(user.id, json)

      # Verify deletion
      assert Repo.get(Data, data_record.id) == nil
    end

    test "returns true for non-existent data (idempotent)" do
      {user, _x, _ed} = create_test_user()

      json =
        Jason.encode!(%{
          action: "delete_data",
          data_id: 999_999,
          device_id: user.id
        })

      assert {:ok, true} = Commands.handle(user.id, json)
    end
  end

  # ==============================================================
  # Error Handling Tests
  # ==============================================================

  describe "error handling" do
    test "returns error for missing action" do
      json = Jason.encode!(%{})
      assert {:error, "Missing action"} = Commands.handle(1, json)
    end

    test "returns error for invalid JSON" do
      assert {:error, "Invalid JSON"} = Commands.handle(1, "not json")
    end

    test "returns error for unknown action" do
      json = Jason.encode!(%{action: "unknown_action"})
      assert {:error, "Not implemented"} = Commands.handle(1, json)
    end
  end

  # ==============================================================
  # send_to Command Tests (requires registry setup)
  # ==============================================================

  describe "send_to action" do
    test "returns error when target is offline" do
      {user, x_public, ed_public} = create_test_user()

      json =
        Jason.encode!(%{
          action: "send_to",
          user_id: user.id,
          x: to_hex(x_public),
          ed: to_hex(ed_public),
          body: "test message"
        })

      assert {:error, "offline"} = Commands.handle(1, json)
    end
  end
end

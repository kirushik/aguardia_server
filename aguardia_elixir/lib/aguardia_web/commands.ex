defmodule AguardiaWeb.Commands do
  @moduledoc """
  Handles JSON commands sent via the WebSocket protocol (cmd=0x00).

  All commands are authenticated - the user_id is always known.
  Commands support "remote control" authorization where providing
  valid x/ed keys for a device allows operations on it.
  """

  require Logger

  alias Aguardia.Crypto
  alias Aguardia.Schema.{User, Data}
  alias Aguardia.ServerState

  @doc """
  Handle a JSON command from an authenticated user.

  Returns {:ok, result} or {:error, reason}.
  """
  @spec handle(integer(), String.t()) :: {:ok, term()} | {:error, String.t()}
  def handle(user_id, json_text) do
    case Jason.decode(json_text) do
      {:ok, %{"action" => action} = params} when is_binary(action) ->
        handle_action(action, params, user_id)

      {:ok, %{"action" => _}} ->
        {:error, "Invalid action type"}

      {:ok, _} ->
        {:error, "Missing action"}

      {:error, _} ->
        {:error, "Invalid JSON"}
    end
  end

  # ============================================================
  # Action Handlers
  # ============================================================

  defp handle_action("status", _params, _user_id) do
    {:ok, true}
  end

  defp handle_action("my_id", _params, user_id) do
    {:ok, user_id}
  end

  defp handle_action("get_id", params, _user_id) do
    with {:ok, x} <- get_key(params, "x"),
         {:ok, ed} <- get_key(params, "ed") do
      case User.get_id_by_keys(x, ed) do
        {:ok, id} -> {:ok, id}
        {:error, :not_found} -> {:ok, false}
      end
    end
  end

  defp handle_action("is_online", params, _user_id) do
    with {:ok, target_id} <- get_int(params, "user_id"),
         {:ok, x} <- get_key(params, "x"),
         {:ok, ed} <- get_key(params, "ed") do
      online = is_online?(target_id, x, ed)
      {:ok, online}
    end
  end

  defp handle_action("send_to", params, _user_id) do
    with {:ok, target_id} <- get_int(params, "user_id"),
         {:ok, x} <- get_key(params, "x"),
         {:ok, ed} <- get_key(params, "ed"),
         {:ok, body} <- get_string(params, "body") do
      # Check if target is online with matching keys
      if not is_online?(target_id, x, ed) do
        {:error, "offline"}
      else
        # Build and send message
        case send_server_message(target_id, x, body) do
          :ok -> {:ok, true}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  defp handle_action("my_info", _params, user_id) do
    case User.get_info(user_id) do
      {:ok, info} -> {:ok, info}
      {:error, :not_found} -> {:error, "user not found"}
    end
  end

  defp handle_action("update_my_info", params, user_id) do
    info = Map.get(params, "info")

    if is_nil(info) do
      {:error, "no info"}
    else
      case User.update_info(user_id, info) do
        :ok -> {:ok, true}
        {:error, :not_found} -> {:error, "user not found"}
        {:error, _} -> {:error, "update failed"}
      end
    end
  end

  defp handle_action("create_new_device", params, user_id) do
    with {:ok, name} <- get_string(params, "name"),
         {:ok, x} <- get_key(params, "x"),
         {:ok, ed} <- get_key(params, "ed") do
      info = %{"name" => name}
      admin_info = %{"created_by" => user_id, "name" => name}

      case User.create_device(x, ed, info) do
        {:ok, device} ->
          # Update admin_info separately (schema doesn't include it in create_device)
          {:ok, device.id}

        {:error, :already_exists} ->
          {:error, "already_exists"}

        {:error, _} ->
          {:error, "create failed"}
      end
    end
  end

  defp handle_action("delete_device", params, user_id) do
    with {:ok, device_id} <- get_int(params, "device_id"),
         :ok <- check_device_access(params, user_id, device_id) do
      # Delete device and all associated data
      Data.delete_all_for_device(device_id)

      case User.delete(device_id) do
        :ok -> {:ok, true}
        {:error, :not_found} -> {:ok, true}
      end
    end
  end

  defp handle_action("read_data", params, user_id) do
    with {:ok, device_id} <- get_int(params, "device_id"),
         :ok <- check_device_access(params, user_id, device_id) do
      # Parse time_from and time_to (accept both strings and integers)
      time_from = parse_timestamp(params, "time_from", 0)
      time_to = parse_timestamp(params, "time_to", 9_999_999_999)

      data = Data.read(device_id, time_from, time_to)
      {:ok, data}
    end
  end

  defp handle_action("delete_data", params, user_id) do
    with {:ok, data_id} <- get_int64(params, "data_id"),
         {:ok, device_id} <- get_int(params, "device_id"),
         :ok <- check_device_access(params, user_id, device_id) do
      case Data.delete(data_id, device_id) do
        :ok -> {:ok, true}
        {:error, :not_found} -> {:ok, true}
      end
    end
  end

  defp handle_action(action, _params, _user_id) do
    Logger.warning("Unknown action: #{inspect(action)}")
    {:error, "Not implemented"}
  end

  # ============================================================
  # Authorization Helpers
  # ============================================================

  @doc """
  Check if user has access to a device.

  Access is granted if:
  1. User is an admin
  2. User is the device (same ID)
  3. User provides valid x/ed keys for the device (remote control)
  """
  defp check_device_access(params, user_id, device_id) do
    cond do
      is_admin?(user_id) ->
        :ok

      user_id == device_id ->
        :ok

      true ->
        # Check if x/ed keys are provided and valid
        with {:ok, x} <- get_key(params, "x"),
             {:ok, ed} <- get_key(params, "ed") do
          if User.owns?(device_id, x, ed) do
            :ok
          else
            {:error, "access denied"}
          end
        else
          _ -> {:error, "access denied"}
        end
    end
  end

  defp is_admin?(user_id) do
    admins = Application.get_env(:aguardia, :admins, [])
    user_id in admins
  end

  defp is_online?(user_id, x, ed) do
    case Registry.lookup(Aguardia.SessionRegistry, user_id) do
      [{_pid, %{x: ^x, ed: ^ed}}] -> true
      _ -> false
    end
  end

  # ============================================================
  # Message Sending
  # ============================================================

  defp send_server_message(target_id, target_x, body) do
    # Build message from server (addr=0)
    message_id = :rand.uniform(0xFFFF)

    inner = <<message_id::little-16, 0x00::8, body::binary>>

    case Crypto.encrypt_and_sign(
           inner,
           ServerState.secret_x(),
           ServerState.secret_ed(),
           target_x
         ) do
      {:ok, encrypted} ->
        payload = <<0::little-32, encrypted::binary>>

        # Send to target via registry
        case Registry.lookup(Aguardia.SessionRegistry, target_id) do
          [{pid, _meta}] ->
            send(pid, {:route, 0, payload})
            :ok

          [] ->
            {:error, "send_error"}
        end

      {:error, :message_too_large} ->
        {:error, "message_too_large"}
    end
  end

  # ============================================================
  # Parameter Extraction Helpers
  # ============================================================

  defp get_string(params, key) do
    case Map.get(params, key) do
      nil -> {:error, "no #{key}"}
      val when is_binary(val) -> {:ok, val}
      _ -> {:error, "invalid #{key}"}
    end
  end

  defp get_int(params, key) do
    case Map.get(params, key) do
      nil -> {:error, "no #{key}"}
      val when is_integer(val) -> {:ok, val}
      val when is_binary(val) -> parse_int(val, key)
      _ -> {:error, "invalid #{key}"}
    end
  end

  defp get_int64(params, key) do
    case Map.get(params, key) do
      nil -> {:error, "no #{key}"}
      val when is_integer(val) -> {:ok, val}
      val when is_binary(val) -> parse_int(val, key)
      _ -> {:error, "invalid #{key}"}
    end
  end

  defp parse_int(str, key) do
    case Integer.parse(str) do
      {val, ""} -> {:ok, val}
      _ -> {:error, "invalid #{key}"}
    end
  end

  defp get_key(params, key) do
    case Map.get(params, key) do
      nil ->
        {:error, "no #{key}"}

      hex when is_binary(hex) ->
        case Crypto.hex_decode32(hex) do
          {:ok, bin} -> {:ok, bin}
          {:error, _} -> {:error, "bad #{key}"}
        end

      _ ->
        {:error, "invalid #{key}"}
    end
  end

  @doc """
  Parse a timestamp parameter that can be either a string or integer.
  Returns the parsed value or the default.
  """
  defp parse_timestamp(params, key, default) do
    case Map.get(params, key) do
      nil ->
        default

      val when is_integer(val) ->
        val

      val when is_binary(val) ->
        case Integer.parse(val) do
          {parsed, ""} -> parsed
          _ -> default
        end

      _ ->
        default
    end
  end
end

defmodule AguardiaWeb.SocketHandler do
  @moduledoc """
  Raw WebSocket handler implementing the WebSock behavior.

  Handles both user and device WebSocket connections:
  - `/ws/user/v1/:public_ed` - User connections with login flow
  - `/ws/device/v1/:public_ed` - Device connections (must be pre-registered)

  ## Protocol

  Binary messages follow this format:
  - `<<addr::little-32, encrypted::binary>>`
  - If addr != 0: Route to user with that ID
  - If addr == 0: Server command

  Encrypted payload format:
  - `<<nonce::little-64, ciphertext::binary, signature::binary-64>>`

  Decrypted message format:
  - `<<message_id::little-16, cmd::8, body::binary>>`
  """
  @behaviour WebSock

  require Logger

  alias Aguardia.Crypto
  alias Aguardia.ServerState
  alias Aguardia.Schema.User
  alias AguardiaWeb.Commands

  # Connection state struct
  defmodule State do
    @moduledoc false
    defstruct [
      :mode,
      :public_ed,
      :login_stage,
      :login_hash,
      :login_email,
      :login_code,
      :user_id,
      :public_x,
      :last_activity,
      :heartbeat_ref
    ]
  end

  # ============================================================
  # WebSock Callbacks
  # ============================================================

  @impl WebSock
  def init(state) do
    # Look up user in database
    case User.get_by_public_ed(state.public_ed) do
      nil ->
        # User not found
        if state.mode == :user do
          # Start login flow
          hash = Crypto.seed() |> Crypto.hex_encode()
          state = %{state | login_hash: hash, login_stage: 0}

          schedule_heartbeat()
          msg = Jason.encode!(%{action: "login", hash: hash})
          {:push, {:text, msg}, state}
        else
          # Device must be pre-registered
          {:stop, :normal, {1008, "Unknown device"}, state}
        end

      user ->
        # User found, authenticate directly
        start_authenticated_session(user, state)
    end
  end

  @impl WebSock
  def handle_in({data, opts}, state) do
    state = %{state | last_activity: System.monotonic_time(:second)}

    case Keyword.get(opts, :opcode) do
      :text ->
        handle_text_message(data, state)

      :binary ->
        handle_binary_message(data, state)

      _ ->
        {:ok, state}
    end
  end

  @impl WebSock
  def handle_info(:heartbeat_check, state) do
    now = System.monotonic_time(:second)
    heartbeat_timeout = Application.get_env(:aguardia, :heartbeat_timeout, 90)
    ping_timeout = Application.get_env(:aguardia, :ping_timeout, 30)

    cond do
      now - state.last_activity > heartbeat_timeout ->
        Logger.debug("WebSocket timeout for user #{state.user_id}")
        {:stop, :normal, state}

      now - state.last_activity > ping_timeout ->
        schedule_heartbeat()
        {:push, {:ping, <<>>}, state}

      true ->
        schedule_heartbeat()
        {:ok, state}
    end
  end

  def handle_info({:route, sender_id, payload}, state) do
    # Message routed from another user
    # Rewrite the first 4 bytes with sender_id
    <<_addr::binary-4, rest::binary>> = payload
    new_payload = <<sender_id::little-32, rest::binary>>
    {:push, {:binary, new_payload}, state}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl WebSock
  def handle_control({:ping, _data}, state) do
    state = %{state | last_activity: System.monotonic_time(:second)}
    {:ok, state}
  end

  def handle_control({:pong, _data}, state) do
    state = %{state | last_activity: System.monotonic_time(:second)}
    {:ok, state}
  end

  @impl WebSock
  def terminate(reason, state) do
    if state.user_id do
      Logger.debug("WebSocket disconnected: user=#{state.user_id} reason=#{inspect(reason)}")
    end

    :ok
  end

  # ============================================================
  # Text Message Handling (Login Flow)
  # ============================================================

  defp handle_text_message(data, %{user_id: nil} = state) do
    # Not authenticated, expect login commands
    case Jason.decode(data) do
      {:ok, %{"type" => "email"} = cmd} ->
        handle_email_command(cmd, state)

      {:ok, %{"type" => "code"} = cmd} ->
        handle_code_command(cmd, state)

      {:ok, _} ->
        error_response("Invalid command", state)

      {:error, _} ->
        error_response("Invalid JSON", state)
    end
  end

  defp handle_text_message(_data, state) do
    # Authenticated users don't use text messages
    {:ok, state}
  end

  defp handle_email_command(
         %{"email" => email, "signature" => sig_hex},
         %{login_stage: 0, login_hash: hash, public_ed: public_ed} = state
       ) do
    # Validate email format
    if not valid_email?(email) do
      error_close("Invalid email format", state)
    else
      # Verify signature over "{hash}/email/{email}"
      payload = "#{hash}/email/#{email}"

      case verify_client_signature(payload, sig_hex, public_ed) do
        :ok ->
          # Get or create email code
          {code, is_new} = Aguardia.EmailCodes.get_or_create(email)

          # Send email if new code
          if is_new do
            case Aguardia.Mailer.send_login_code(email, code) do
              :ok ->
                state = %{state | login_stage: 1, login_email: email, login_code: code}
                msg = Jason.encode!(%{action: "code_sent", hash: hash})
                {:push, {:text, msg}, state}

              {:error, reason} ->
                error_close("Email error: #{inspect(reason)}", state)
            end
          else
            state = %{state | login_stage: 1, login_email: email, login_code: code}
            msg = Jason.encode!(%{action: "code_already_sent", hash: hash})
            {:push, {:text, msg}, state}
          end

        {:error, _} ->
          error_close("Signature failed", state)
      end
    end
  end

  defp handle_email_command(_, state) do
    error_close("Invalid stage", state)
  end

  defp handle_code_command(
         %{"code" => received_code, "x_public" => x_public_hex, "signature" => sig_hex},
         %{
           login_stage: 1,
           login_hash: hash,
           login_email: email,
           login_code: code,
           public_ed: public_ed
         } = state
       ) do
    # Verify code matches
    if received_code != code do
      error_close("Invalid code", state)
    else
      # Verify signature over "{hash}/code/{code}/{x_public}"
      payload = "#{hash}/code/#{code}/#{x_public_hex}"

      with :ok <- verify_client_signature(payload, sig_hex, public_ed),
           {:ok, public_x} <- Crypto.hex_decode32(x_public_hex) do
        # Upsert user in database
        case User.upsert_by_email(email, public_x, public_ed) do
          {:ok, user} ->
            # Clear email code
            Aguardia.EmailCodes.delete(email)

            # Start authenticated session
            start_authenticated_session_with_login_success(user, public_x, state)

          {:error, reason} ->
            Logger.error("DB error during login: #{inspect(reason)}")
            error_close("DB error", state)
        end
      else
        {:error, :invalid_hex} ->
          error_close("Invalid x_public", state)

        {:error, :invalid_length} ->
          error_close("Invalid x_public length", state)

        {:error, reason} ->
          error_close("Signature failed: #{inspect(reason)}", state)
      end
    end
  end

  defp handle_code_command(_, state) do
    error_close("Invalid stage", state)
  end

  # ============================================================
  # Binary Message Handling (Authenticated)
  # ============================================================

  defp handle_binary_message(data, %{user_id: nil} = state) do
    # Not authenticated, ignore binary messages
    Logger.warning("Received binary message from unauthenticated client")
    {:ok, state}
  end

  defp handle_binary_message(data, state) when byte_size(data) < 5 do
    Logger.warning("Packet too short: #{byte_size(data)} bytes")
    {:ok, state}
  end

  defp handle_binary_message(<<addr::little-32, encrypted::binary>>, state) do
    if addr != 0 do
      # Route to another user
      route_message(addr, state.user_id, encrypted, state)
    else
      # Server command
      handle_server_command(encrypted, state)
    end
  end

  defp route_message(target_id, sender_id, payload, state) do
    # Look up target in registry
    case Registry.lookup(Aguardia.SessionRegistry, target_id) do
      [{pid, _meta}] ->
        # Build full message with sender_id in first 4 bytes
        full_message = <<sender_id::little-32, payload::binary>>
        send(pid, {:route, sender_id, full_message})
        Logger.debug("Routed message from #{sender_id} to #{target_id}")
        {:ok, state}

      [] ->
        Logger.warning("Failed to route to #{target_id}: offline")
        msg = {:text, "Failed to route"}
        {:push, msg, state}
    end
  end

  defp handle_server_command(encrypted, state) do
    # Verify and decrypt
    result =
      Crypto.verify_and_decrypt(
        encrypted,
        ServerState.secret_x(),
        state.public_x,
        state.public_ed,
        5
      )

    case result do
      {:ok, <<message_id::little-16, cmd::8, body::binary>>} ->
        # Process command and build response
        response_body = process_command(cmd, body, state)

        # Encrypt response
        inner = <<message_id::little-16, 0x01::8, response_body::binary>>

        response =
          Crypto.encrypt_and_sign(
            inner,
            ServerState.secret_x(),
            ServerState.secret_ed(),
            state.public_x
          )

        # Prepend server address (0)
        payload = <<0::little-32, response::binary>>
        {:push, {:binary, payload}, state}

      {:ok, _} ->
        Logger.warning("Malformed decrypted packet")
        {:ok, state}

      {:error, :bad_nonce} ->
        Logger.warning("Bad nonce (timestamp)")
        msg = {:text, "timestamp_error:#{Crypto.get_unixtime()}"}
        {:push, msg, state}

      {:error, :bad_signature} ->
        Logger.warning("Bad signature")
        {:ok, state}

      {:error, :bad_format} ->
        Logger.warning("Bad packet format")
        {:ok, state}

      {:error, :decrypt_failed} ->
        Logger.warning("Decryption failed")
        {:ok, state}
    end
  end

  defp process_command(0x00, body, state) do
    # JSON command
    text = to_string(body)
    Logger.debug("Command 0x00: #{text}")

    case Commands.handle(state.user_id, text) do
      {:ok, result} -> Jason.encode!(result)
      {:error, reason} -> Jason.encode!(%{error: reason})
    end
  end

  defp process_command(0x10, body, state) do
    # Telemetry data
    Logger.debug("Command 0x10: telemetry")

    case Jason.decode(body) do
      {:ok, payload} ->
        case Aguardia.Schema.Data.insert(state.user_id, payload) do
          {:ok, _} -> Jason.encode!(%{result: true})
          {:error, _} -> Jason.encode!(%{error: "db_error"})
        end

      {:error, _} ->
        Jason.encode!(%{error: "Invalid JSON"})
    end
  end

  defp process_command(cmd, _body, _state) do
    Logger.warning("Unknown command: 0x#{Integer.to_string(cmd, 16)}")
    Jason.encode!(%{error: "Invalid cmd"})
  end

  # ============================================================
  # Session Management
  # ============================================================

  defp start_authenticated_session(user, state) do
    # Register in session registry
    Registry.register(Aguardia.SessionRegistry, user.id, %{
      x: user.public_x,
      ed: user.public_ed
    })

    state = %{state | user_id: user.id, public_x: user.public_x, login_stage: 2}

    Logger.info("WebSocket authenticated: user=#{user.id}")
    schedule_heartbeat()

    {:ok, state}
  end

  defp start_authenticated_session_with_login_success(user, public_x, state) do
    # Register in session registry
    Registry.register(Aguardia.SessionRegistry, user.id, %{
      x: public_x,
      ed: state.public_ed
    })

    state = %{state | user_id: user.id, public_x: public_x, login_stage: 2}

    Logger.info("WebSocket authenticated via login: user=#{user.id}")
    schedule_heartbeat()

    # Send login success message
    msg =
      Jason.encode!(%{
        action: "login_success",
        my_id: user.id,
        server_X: Crypto.hex_encode(ServerState.public_x()),
        server_ed: Crypto.hex_encode(ServerState.public_ed())
      })

    {:push, {:text, msg}, state}
  end

  # ============================================================
  # Helpers
  # ============================================================

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat_check, 5_000)
  end

  defp verify_client_signature(payload, sig_hex, public_ed) do
    case Crypto.hex_decode64(sig_hex) do
      {:ok, signature} ->
        if Crypto.verify(payload, signature, public_ed) do
          :ok
        else
          {:error, :bad_signature}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_email?(email) do
    String.contains?(email, "@") and
      String.contains?(email, ".") and
      String.length(email) >= 5 and
      String.length(email) <= 256
  end

  defp error_response(msg, state) do
    {:push, {:text, Jason.encode!(%{error: msg})}, state}
  end

  defp error_close(msg, state) do
    Logger.warning("WebSocket error: #{msg}")
    {:stop, :normal, {1008, msg}, [{:text, Jason.encode!(%{error: msg})}], state}
  end
end

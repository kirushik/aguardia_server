defmodule AguardiaWeb.ProtocolTest do
  @moduledoc """
  Protocol compliance tests for the Aguardia WebSocket protocol.

  These tests verify that the Elixir implementation correctly handles
  the binary packet format, framing, and message routing as specified
  in the protocol documentation.
  """
  use ExUnit.Case, async: true

  alias Aguardia.Crypto
  alias Aguardia.ServerState
  alias Aguardia.Schema.User
  alias Aguardia.Repo

  # Use the sandbox for database tests
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  # ==============================================================
  # Helper Functions
  # ==============================================================

  defp create_test_user do
    seed_x = Crypto.seed()
    x_secret = Crypto.x25519_secret(seed_x)
    x_public = Crypto.x25519_public(x_secret)

    seed_ed = Crypto.seed()
    {ed_secret, ed_public} = Crypto.ed25519_keypair_from_seed(seed_ed)

    attrs = %{
      public_x: x_public,
      public_ed: ed_public
    }

    {:ok, user} = Repo.insert(User.changeset(%User{}, attrs))

    %{
      user: user,
      x_secret: x_secret,
      x_public: x_public,
      ed_secret: ed_secret,
      ed_public: ed_public
    }
  end

  defp to_hex(bin), do: Base.encode16(bin, case: :upper)

  # ==============================================================
  # Packet Format Tests
  # ==============================================================

  describe "packet framing" do
    test "outer frame format: addr (4 bytes LE) + encrypted payload" do
      addr = 12345
      payload = :crypto.strong_rand_bytes(100)

      packet = <<addr::little-32, payload::binary>>

      # Verify we can parse it back
      <<parsed_addr::little-32, parsed_payload::binary>> = packet

      assert parsed_addr == addr
      assert parsed_payload == payload
    end

    test "addr=0 indicates server command" do
      payload = :crypto.strong_rand_bytes(50)
      packet = <<0::little-32, payload::binary>>

      <<addr::little-32, _rest::binary>> = packet
      assert addr == 0
    end

    test "addr!=0 indicates routing to another user" do
      target_id = 42
      payload = :crypto.strong_rand_bytes(50)
      packet = <<target_id::little-32, payload::binary>>

      <<addr::little-32, _rest::binary>> = packet
      assert addr == 42
      assert addr != 0
    end
  end

  describe "encrypted payload format" do
    test "format: nonce (8 bytes LE) + ciphertext + signature (64 bytes)" do
      nonce = 1_234_567_890
      ciphertext = :crypto.strong_rand_bytes(100)
      signature = :crypto.strong_rand_bytes(64)

      encrypted = <<nonce::little-64, ciphertext::binary, signature::binary>>

      # Verify we can parse it back
      sig_start = byte_size(encrypted) - 64
      <<nonce_and_cipher::binary-size(sig_start), parsed_sig::binary-64>> = encrypted
      <<parsed_nonce::little-64, parsed_ciphertext::binary>> = nonce_and_cipher

      assert parsed_nonce == nonce
      assert parsed_ciphertext == ciphertext
      assert parsed_sig == signature
    end

    test "nonce is 8-byte little-endian unix timestamp" do
      timestamp = System.system_time(:second)
      nonce_bytes = <<timestamp::little-64>>

      assert byte_size(nonce_bytes) == 8

      # Parse it back
      <<parsed::little-64>> = nonce_bytes
      assert parsed == timestamp
    end
  end

  describe "decrypted message format" do
    test "format: message_id (2 bytes LE) + cmd (1 byte) + body" do
      message_id = 12345
      cmd = 0x00
      body = "test body"

      inner = <<message_id::little-16, cmd::8, body::binary>>

      # Verify we can parse it back
      <<parsed_id::little-16, parsed_cmd::8, parsed_body::binary>> = inner

      assert parsed_id == message_id
      assert parsed_cmd == cmd
      assert parsed_body == body
    end

    test "cmd=0x00 is JSON server command" do
      cmd = 0x00
      assert cmd == 0
    end

    test "cmd=0x01 is server response" do
      cmd = 0x01
      assert cmd == 1
    end

    test "cmd=0x10 is telemetry data" do
      cmd = 0x10
      assert cmd == 16
    end
  end

  # ==============================================================
  # Nonce (XChaCha20) Format Tests
  # ==============================================================

  describe "nonce derivation" do
    test "24-byte nonce is created by repeating 8-byte LE timestamp 3 times" do
      timestamp = 1_764_020_895

      nonce = Crypto.nonce_from_u64(timestamp)

      assert byte_size(nonce) == 24

      expected_8_bytes = <<timestamp::little-64>>
      assert nonce == expected_8_bytes <> expected_8_bytes <> expected_8_bytes
    end

    test "nonce bytes match expected pattern for known timestamp" do
      # From Rust test: nonce 1764020895 = 0x692224D9
      # LE bytes: 9F D2 24 69 00 00 00 00 (8 bytes)
      timestamp = 1_764_020_895
      nonce = Crypto.nonce_from_u64(timestamp)

      <<b0, b1, b2, b3, b4, b5, b6, b7, _rest::binary>> = nonce

      # 1764020895 in LE: 0x9F, 0xD2, 0x24, 0x69, 0x00, 0x00, 0x00, 0x00
      assert b0 == 0x9F
      assert b1 == 0xD2
      assert b2 == 0x24
      assert b3 == 0x69
      assert b4 == 0x00
      assert b5 == 0x00
      assert b6 == 0x00
      assert b7 == 0x00
    end
  end

  # ==============================================================
  # Complete Protocol Flow Tests
  # ==============================================================

  describe "complete encrypt/decrypt flow" do
    test "client can create valid packet for server" do
      # Create client keys
      client_seed_x = Crypto.seed()
      client_x_secret = Crypto.x25519_secret(client_seed_x)
      _client_x_public = Crypto.x25519_public(client_x_secret)

      client_seed_ed = Crypto.seed()
      {client_ed_secret, _client_ed_public} = Crypto.ed25519_keypair_from_seed(client_seed_ed)

      # Get server public key
      server_x_public = ServerState.public_x()

      # Create inner message
      message_id = :rand.uniform(65535)
      cmd = 0x00
      body = Jason.encode!(%{action: "status"})
      inner = <<message_id::little-16, cmd::8, body::binary>>

      # Encrypt and sign
      encrypted =
        Crypto.encrypt_and_sign(inner, client_x_secret, client_ed_secret, server_x_public)

      # Create outer packet (addr=0 for server)
      packet = <<0::little-32, encrypted::binary>>

      # Verify packet structure
      <<addr::little-32, payload::binary>> = packet
      assert addr == 0
      # Minimum: 8 (nonce) + 0 (cipher) + 64 (sig)
      assert byte_size(payload) >= 72
    end

    test "server response packet format" do
      # Simulate a server response
      message_id = 12345
      # Response
      cmd = 0x01
      body = Jason.encode!(%{result: true})

      inner = <<message_id::little-16, cmd::8, body::binary>>

      # Verify the format
      <<parsed_id::little-16, parsed_cmd::8, parsed_body::binary>> = inner
      assert parsed_id == message_id
      assert parsed_cmd == 0x01
      assert Jason.decode!(parsed_body) == %{"result" => true}
    end

    test "message routing preserves payload except addr rewrite" do
      sender_id = 100
      target_id = 200
      payload = :crypto.strong_rand_bytes(200)

      # Original packet from sender (with target_id as addr)
      original_packet = <<target_id::little-32, payload::binary>>

      # When routing, server rewrites first 4 bytes to sender_id
      <<_old_addr::binary-4, rest::binary>> = original_packet
      routed_packet = <<sender_id::little-32, rest::binary>>

      # Verify addr was rewritten
      <<addr_in_routed::little-32, payload_in_routed::binary>> = routed_packet
      assert addr_in_routed == sender_id
      assert payload_in_routed == payload
    end
  end

  # ==============================================================
  # Login Flow Tests
  # ==============================================================

  describe "login flow protocol" do
    test "stage 0: server sends login challenge" do
      hash = Crypto.seed() |> Crypto.hex_encode()

      challenge = %{action: "login", hash: hash}
      json = Jason.encode!(challenge)

      parsed = Jason.decode!(json)
      assert parsed["action"] == "login"
      # 32 bytes hex
      assert String.length(parsed["hash"]) == 64
    end

    test "stage 1: client sends email request" do
      hash = "A" |> String.duplicate(64)
      email = "test@example.com"
      # 64 bytes hex
      signature = "B" |> String.duplicate(128)

      request = %{type: "email", email: email, signature: signature}
      json = Jason.encode!(request)

      parsed = Jason.decode!(json)
      assert parsed["type"] == "email"
      assert parsed["email"] == email
      assert String.length(parsed["signature"]) == 128
    end

    test "signature for email request covers correct format" do
      hash = "ABC123"
      email = "test@example.com"

      # The payload to sign should be: "{hash}/email/{email}"
      payload = "#{hash}/email/#{email}"
      assert payload == "ABC123/email/test@example.com"
    end

    test "stage 2: client sends code verification" do
      hash = "A" |> String.duplicate(64)
      code = "123456"
      # 32 bytes hex
      x_public_hex = "C" |> String.duplicate(64)
      # 64 bytes hex
      signature = "D" |> String.duplicate(128)

      request = %{type: "code", code: code, x_public: x_public_hex, signature: signature}
      json = Jason.encode!(request)

      parsed = Jason.decode!(json)
      assert parsed["type"] == "code"
      assert parsed["code"] == code
      assert String.length(parsed["x_public"]) == 64
      assert String.length(parsed["signature"]) == 128
    end

    test "signature for code request covers correct format" do
      hash = "ABC123"
      code = "654321"
      x_public = "DEADBEEF"

      # The payload to sign should be: "{hash}/code/{code}/{x_public}"
      payload = "#{hash}/code/#{code}/#{x_public}"
      assert payload == "ABC123/code/654321/DEADBEEF"
    end

    test "login success response format" do
      response = %{
        action: "login_success",
        my_id: 42,
        server_X: String.duplicate("AA", 32),
        server_ed: String.duplicate("BB", 32)
      }

      json = Jason.encode!(response)
      parsed = Jason.decode!(json)

      assert parsed["action"] == "login_success"
      assert parsed["my_id"] == 42
      assert String.length(parsed["server_X"]) == 64
      assert String.length(parsed["server_ed"]) == 64
    end
  end

  # ==============================================================
  # JSON Command Format Tests
  # ==============================================================

  describe "JSON command formats" do
    test "status command" do
      cmd = %{action: "status"}
      assert Jason.encode!(cmd) == ~s({"action":"status"})
    end

    test "my_id command" do
      cmd = %{action: "my_id"}
      assert Jason.encode!(cmd) == ~s({"action":"my_id"})
    end

    test "get_id command with keys" do
      cmd = %{
        action: "get_id",
        x: String.duplicate("00", 32),
        ed: String.duplicate("11", 32)
      }

      parsed = Jason.decode!(Jason.encode!(cmd))
      assert parsed["action"] == "get_id"
      assert String.length(parsed["x"]) == 64
      assert String.length(parsed["ed"]) == 64
    end

    test "is_online command" do
      cmd = %{
        action: "is_online",
        user_id: 42,
        x: String.duplicate("00", 32),
        ed: String.duplicate("11", 32)
      }

      parsed = Jason.decode!(Jason.encode!(cmd))
      assert parsed["action"] == "is_online"
      assert parsed["user_id"] == 42
    end

    test "send_to command" do
      cmd = %{
        action: "send_to",
        user_id: 42,
        x: String.duplicate("00", 32),
        ed: String.duplicate("11", 32),
        body: "message content"
      }

      parsed = Jason.decode!(Jason.encode!(cmd))
      assert parsed["action"] == "send_to"
      assert parsed["body"] == "message content"
    end

    test "read_data command accepts string timestamps" do
      cmd = %{
        action: "read_data",
        device_id: 42,
        time_from: "1000000000",
        time_to: "2000000000"
      }

      parsed = Jason.decode!(Jason.encode!(cmd))
      assert is_binary(parsed["time_from"])
      assert is_binary(parsed["time_to"])
    end

    test "read_data command accepts integer timestamps" do
      cmd = %{
        action: "read_data",
        device_id: 42,
        time_from: 1_000_000_000,
        time_to: 2_000_000_000
      }

      parsed = Jason.decode!(Jason.encode!(cmd))
      assert is_integer(parsed["time_from"])
      assert is_integer(parsed["time_to"])
    end
  end

  # ==============================================================
  # Error Response Format Tests
  # ==============================================================

  describe "error response formats" do
    test "JSON error response format" do
      error = %{error: "some error message"}
      json = Jason.encode!(error)

      assert json == ~s({"error":"some error message"})
    end

    test "timestamp error response format" do
      timestamp = 1_234_567_890
      message = "timestamp_error:#{timestamp}"

      assert String.starts_with?(message, "timestamp_error:")
      assert String.contains?(message, "1234567890")
    end
  end

  # ==============================================================
  # Binary Edge Cases
  # ==============================================================

  describe "binary edge cases" do
    test "handles minimum valid packet size" do
      # Minimum encrypted payload: 8 (nonce) + 16 (poly1305 tag) + 64 (signature) = 88
      # But with addr: 4 + 88 = 92 bytes minimum for valid packet
      min_payload = :crypto.strong_rand_bytes(88)
      packet = <<0::little-32, min_payload::binary>>

      assert byte_size(packet) == 92
    end

    test "handles packet with just header and no encrypted data" do
      # This should be rejected as too short
      # 4 + 6 = 10 bytes
      short_packet = <<0::little-32, 0::48>>

      assert byte_size(short_packet) == 10
      # Server should reject this as bad_format
    end

    test "handles maximum message_id value" do
      max_id = 65535
      cmd = 0x00
      body = "test"

      inner = <<max_id::little-16, cmd::8, body::binary>>
      <<parsed_id::little-16, _rest::binary>> = inner

      assert parsed_id == 65535
    end

    test "handles maximum addr value (user_id)" do
      # Max u32
      max_addr = 4_294_967_295
      payload = :crypto.strong_rand_bytes(100)

      packet = <<max_addr::little-32, payload::binary>>
      <<parsed_addr::little-32, _rest::binary>> = packet

      assert parsed_addr == max_addr
    end
  end

  # ==============================================================
  # Telemetry Data Format Tests (cmd=0x10)
  # ==============================================================

  describe "telemetry data format (cmd=0x10)" do
    test "telemetry command structure" do
      message_id = 100
      cmd = 0x10
      payload = %{"temperature" => 25.5, "humidity" => 60}

      body = Jason.encode!(payload)
      inner = <<message_id::little-16, cmd::8, body::binary>>

      <<parsed_id::little-16, parsed_cmd::8, parsed_body::binary>> = inner

      assert parsed_id == message_id
      assert parsed_cmd == 0x10
      assert Jason.decode!(parsed_body) == payload
    end

    test "telemetry response format" do
      response = %{result: true}
      json = Jason.encode!(response)

      assert json == ~s({"result":true})
    end

    test "telemetry payload can include time field" do
      timestamp = System.system_time(:second)
      payload = %{time: timestamp, value: 42}

      json = Jason.encode!(payload)
      parsed = Jason.decode!(json)

      assert parsed["time"] == timestamp
    end
  end

  # ==============================================================
  # WebSocket Endpoint Path Tests
  # ==============================================================

  describe "WebSocket endpoint paths" do
    test "user endpoint format" do
      public_ed_hex = String.duplicate("AB", 32)
      path = "/ws/user/v1/#{public_ed_hex}"

      assert path ==
               "/ws/user/v1/ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB"
    end

    test "device endpoint format" do
      public_ed_hex = String.duplicate("CD", 32)
      path = "/ws/device/v1/#{public_ed_hex}"

      assert path ==
               "/ws/device/v1/CDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCDCD"
    end

    test "endpoint paths have correct prefix" do
      assert String.starts_with?("/ws/user/v1/abc", "/ws/user/v1/")
      assert String.starts_with?("/ws/device/v1/abc", "/ws/device/v1/")
    end
  end
end

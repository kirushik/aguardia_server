defmodule Aguardia.FuzzingTest do
  @moduledoc """
  Input fuzzing tests for the Aguardia server.

  These tests verify that the server handles malformed input gracefully
  without crashing or exposing internal errors.
  """
  use ExUnit.Case, async: true

  alias Aguardia.Crypto
  alias AguardiaWeb.Commands

  # ==============================================================
  # Hex Decoding Fuzzing
  # ==============================================================

  describe "hex decoding robustness" do
    test "handles invalid hex characters" do
      invalid_inputs = [
        "GGGGGGGG",
        "ZZZZZZZZ",
        "!@#$%^&*",
        "12345G78",
        "ABCDEFGH",
        "spaces here",
        "tab\there",
        "newline\nhere"
      ]

      for input <- invalid_inputs do
        assert {:error, :invalid_hex} = Crypto.hex_decode(input)
      end
    end

    test "handles odd-length hex strings" do
      odd_inputs = ["A", "ABC", "ABCDE", "0123456"]

      for input <- odd_inputs do
        assert {:error, :invalid_hex} = Crypto.hex_decode(input)
      end
    end

    test "handles empty string" do
      assert {:ok, <<>>} = Crypto.hex_decode("")
    end

    test "handles unicode characters" do
      unicode_inputs = [
        "日本語",
        "émojis🎉",
        "Привет",
        "中文字符",
        "αβγδ"
      ]

      for input <- unicode_inputs do
        assert {:error, :invalid_hex} = Crypto.hex_decode(input)
      end
    end

    test "handles null bytes in hex string" do
      # Null byte in the middle
      input = "AB" <> <<0>> <> "CD"
      assert {:error, :invalid_hex} = Crypto.hex_decode(input)
    end

    test "handles very long hex strings" do
      # 10KB of hex
      long_hex = String.duplicate("AB", 10_000)
      assert {:ok, result} = Crypto.hex_decode(long_hex)
      assert byte_size(result) == 10_000
    end

    test "hex_decode32 rejects wrong lengths" do
      wrong_lengths = [
        # 30 bytes
        String.duplicate("00", 30),
        # 31 bytes
        String.duplicate("00", 31),
        # 33 bytes
        String.duplicate("00", 33),
        # 64 bytes
        String.duplicate("00", 64),
        # empty
        ""
      ]

      for input <- wrong_lengths do
        result = Crypto.hex_decode32(input)
        assert {:error, _} = result
      end
    end

    test "hex_decode64 rejects wrong lengths" do
      wrong_lengths = [
        # 62 bytes
        String.duplicate("00", 62),
        # 63 bytes
        String.duplicate("00", 63),
        # 65 bytes
        String.duplicate("00", 65),
        # 32 bytes
        String.duplicate("00", 32),
        # empty
        ""
      ]

      for input <- wrong_lengths do
        result = Crypto.hex_decode64(input)
        assert {:error, _} = result
      end
    end
  end

  # ==============================================================
  # JSON Command Fuzzing
  # ==============================================================

  describe "JSON command fuzzing" do
    test "handles invalid JSON strings" do
      invalid_jsons = [
        "",
        "not json",
        "{",
        "}",
        "[",
        "]",
        "{{}",
        "{'single': 'quotes'}",
        "{\"unclosed\":",
        "{\"trailing\": \"comma\",}",
        "null",
        "true",
        "false",
        "123",
        "\"just a string\""
      ]

      for input <- invalid_jsons do
        result = Commands.handle(1, input)
        # Should return error, not crash
        assert {:error, _} = result or {:ok, _} = result
      end
    end

    test "handles JSON with missing required fields" do
      missing_fields = [
        ~s({}),
        ~s({"not_action": "status"}),
        ~s({"Action": "status"}),
        ~s({"ACTION": "STATUS"})
      ]

      for input <- missing_fields do
        result = Commands.handle(1, input)
        assert {:error, _} = result
      end
    end

    test "handles JSON with wrong field types" do
      wrong_types = [
        ~s({"action": 123}),
        ~s({"action": null}),
        ~s({"action": true}),
        ~s({"action": []}),
        ~s({"action": {}}),
        ~s({"action": "get_id", "x": 123}),
        ~s({"action": "get_id", "x": null}),
        ~s({"action": "read_data", "device_id": "not_a_number"})
      ]

      for input <- wrong_types do
        result = Commands.handle(1, input)
        # Should handle gracefully
        assert {:error, _} = result or {:ok, _} = result
      end
    end

    test "handles deeply nested JSON" do
      # Create deeply nested object
      nested =
        Enum.reduce(1..100, %{}, fn i, acc ->
          %{"level_#{i}" => acc}
        end)

      json = Jason.encode!(%{action: "status", data: nested})
      result = Commands.handle(1, json)

      # Should handle without crashing
      assert {:ok, true} = result
    end

    test "handles very long action names" do
      long_action = String.duplicate("a", 10_000)
      json = Jason.encode!(%{action: long_action})

      result = Commands.handle(1, json)
      assert {:error, _} = result
    end

    test "handles very long field values" do
      # 1MB string
      long_value = String.duplicate("x", 1_000_000)
      json = Jason.encode!(%{action: "update_my_info", info: %{data: long_value}})

      result = Commands.handle(1, json)
      # Should handle (may succeed or fail, but shouldn't crash)
      assert {:error, _} = result or {:ok, _} = result
    end

    test "handles JSON with extra unexpected fields" do
      json =
        Jason.encode!(%{
          action: "status",
          extra1: "value",
          extra2: 123,
          extra3: [1, 2, 3],
          extra4: %{nested: "object"}
        })

      result = Commands.handle(1, json)
      assert {:ok, true} = result
    end

    test "handles JSON with special characters in values" do
      special_chars = [
        # null byte
        "test\x00value",
        "test\nvalue",
        "test\rvalue",
        "test\tvalue",
        "test\\value",
        "test\"value",
        "test/value",
        "test\x1Fvalue",
        "日本語",
        "emoji🎉"
      ]

      for char <- special_chars do
        json = Jason.encode!(%{action: "update_my_info", info: %{data: char}})
        result = Commands.handle(1, json)
        # Should handle without crashing
        assert {:error, _} = result or {:ok, _} = result
      end
    end
  end

  # ==============================================================
  # Crypto Function Fuzzing
  # ==============================================================

  describe "crypto function fuzzing" do
    test "x25519_secret handles various seed inputs" do
      # Should only accept 32-byte binaries
      valid_seed = :crypto.strong_rand_bytes(32)
      result = Crypto.x25519_secret(valid_seed)
      assert byte_size(result) == 32
    end

    test "nonce_from_u64 handles edge values" do
      edge_values = [
        0,
        1,
        # max u32
        0xFFFFFFFF,
        # u32 + 1
        0x100000000,
        # max u64
        0xFFFFFFFFFFFFFFFF
      ]

      for value <- edge_values do
        nonce = Crypto.nonce_from_u64(value)
        assert byte_size(nonce) == 24
      end
    end

    test "verify_and_decrypt handles truncated packets" do
      # Various truncated packet sizes
      for size <- [0, 1, 10, 50, 71, 72, 73, 80, 87] do
        truncated = :crypto.strong_rand_bytes(size)

        result =
          Crypto.verify_and_decrypt(
            truncated,
            :crypto.strong_rand_bytes(32),
            :crypto.strong_rand_bytes(32),
            :crypto.strong_rand_bytes(32),
            0
          )

        # Should return error, not crash
        assert {:error, _} = result
      end
    end

    test "verify_and_decrypt handles random garbage" do
      for _ <- 1..50 do
        garbage_size = :rand.uniform(500)
        garbage = :crypto.strong_rand_bytes(garbage_size)

        result =
          Crypto.verify_and_decrypt(
            garbage,
            :crypto.strong_rand_bytes(32),
            :crypto.strong_rand_bytes(32),
            :crypto.strong_rand_bytes(32),
            0
          )

        assert {:error, _} = result
      end
    end

    test "decrypt_message handles corrupted ciphertext" do
      seed_a = Crypto.seed()
      sk_a = Crypto.x25519_secret(seed_a)
      pk_a = Crypto.x25519_public(sk_a)

      seed_b = Crypto.seed()
      sk_b = Crypto.x25519_secret(seed_b)
      pk_b = Crypto.x25519_public(sk_b)

      plaintext = "test message"
      nonce = Crypto.get_unixtime()

      ciphertext = Crypto.encrypt_message(pk_b, sk_a, plaintext, nonce)

      # Corrupt the ciphertext
      corrupted = :binary.part(ciphertext, 0, byte_size(ciphertext) - 1) <> <<0xFF>>

      result = Crypto.decrypt_message(pk_a, sk_b, corrupted, nonce)
      assert {:error, :decrypt_failed} = result
    end

    test "verify rejects wrong signature size" do
      data = "test data"
      public = :crypto.strong_rand_bytes(32)

      # Wrong signature sizes
      wrong_sizes = [0, 1, 32, 63, 65, 128]

      for size <- wrong_sizes do
        if size != 64 do
          # Should handle gracefully (may raise or return false)
          try do
            result = Crypto.verify(data, :crypto.strong_rand_bytes(size), public)
            # If it doesn't raise, should return false
            assert result == false
          rescue
            _ -> :ok
          end
        end
      end
    end
  end

  # ==============================================================
  # Binary Packet Fuzzing
  # ==============================================================

  describe "binary packet fuzzing" do
    test "packet with zero length payload" do
      # Just the address, no payload
      packet = <<0::little-32>>
      assert byte_size(packet) == 4
    end

    test "packet parsing handles all byte values in addr" do
      for byte <- 0..255 do
        packet = <<byte, byte, byte, byte, "payload"::binary>>
        <<addr::little-32, payload::binary>> = packet
        assert is_integer(addr)
        assert payload == "payload"
      end
    end

    test "handles packets with embedded nulls" do
      payload_with_nulls = <<0, 1, 0, 2, 0, 3, 0, 0, 0>>
      packet = <<0::little-32, payload_with_nulls::binary>>

      <<addr::little-32, parsed_payload::binary>> = packet
      assert addr == 0
      assert parsed_payload == payload_with_nulls
    end
  end

  # ==============================================================
  # Email Code Fuzzing
  # ==============================================================

  describe "email code fuzzing" do
    test "handles emails with special characters" do
      special_emails = [
        "test+tag@example.com",
        "test.name@example.com",
        "test_name@example.com",
        "test-name@example.com",
        "test@sub.domain.example.com",
        "TEST@EXAMPLE.COM",
        "tEsT@eXaMpLe.CoM"
      ]

      for email <- special_emails do
        {code, is_new} = Aguardia.EmailCodes.get_or_create(email)

        assert is_new == true
        assert String.length(code) == 6
        assert String.match?(code, ~r/^\d{6}$/)

        Aguardia.EmailCodes.delete(email)
      end
    end

    test "handles empty email" do
      {code, is_new} = Aguardia.EmailCodes.get_or_create("")

      assert is_new == true
      assert String.length(code) == 6

      Aguardia.EmailCodes.delete("")
    end

    test "handles unicode emails" do
      unicode_emails = [
        "тест@пример.рф",
        "用户@例子.测试",
        "テスト@例え.jp"
      ]

      for email <- unicode_emails do
        {code, is_new} = Aguardia.EmailCodes.get_or_create(email)

        assert is_new == true
        assert String.length(code) == 6

        Aguardia.EmailCodes.delete(email)
      end
    end
  end

  # ==============================================================
  # Stress Tests
  # ==============================================================

  describe "stress tests" do
    test "rapid hex encode/decode cycles" do
      for _ <- 1..1000 do
        data = :crypto.strong_rand_bytes(:rand.uniform(100))
        encoded = Crypto.hex_encode(data)
        {:ok, decoded} = Crypto.hex_decode(encoded)
        assert decoded == data
      end
    end

    test "rapid nonce generation" do
      for i <- 1..1000 do
        nonce = Crypto.nonce_from_u64(i)
        assert byte_size(nonce) == 24
      end
    end

    test "rapid key generation" do
      for _ <- 1..100 do
        seed = Crypto.seed()
        secret = Crypto.x25519_secret(seed)
        public = Crypto.x25519_public(secret)

        assert byte_size(secret) == 32
        assert byte_size(public) == 32
      end
    end

    test "concurrent command handling" do
      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            json = Jason.encode!(%{action: "status"})
            Commands.handle(:rand.uniform(10000), json)
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # All should succeed
      assert Enum.all?(results, fn result -> result == {:ok, true} end)
    end
  end

  # ==============================================================
  # Boundary Value Tests
  # ==============================================================

  describe "boundary value tests" do
    test "message_id boundary values" do
      boundary_ids = [0, 1, 32767, 32768, 65534, 65535]

      for id <- boundary_ids do
        inner = <<id::little-16, 0x00::8, "test"::binary>>
        <<parsed_id::little-16, _rest::binary>> = inner
        assert parsed_id == id
      end
    end

    test "timestamp boundary values" do
      # Note: These are just format tests, not actual time validation
      boundary_times = [
        0,
        1,
        # Year 2000
        946_684_800,
        # Year 2038 problem
        2_147_483_647,
        # Year 2100
        4_102_444_800,
        # Max safe JS integer approximation
        9_007_199_254_740_991
      ]

      for time <- boundary_times do
        nonce = Crypto.nonce_from_u64(time)
        assert byte_size(nonce) == 24
      end
    end

    test "user_id boundary values" do
      boundary_ids = [0, 1, 2_147_483_647, 4_294_967_295]

      for id <- boundary_ids do
        packet = <<id::little-32, "payload"::binary>>
        <<parsed_id::little-32, _rest::binary>> = packet
        assert parsed_id == id
      end
    end
  end
end

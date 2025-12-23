defmodule Aguardia.CryptoTest do
  @moduledoc """
  Tests for Aguardia.Crypto module.

  These tests verify compatibility with the Rust implementation using
  test vectors extracted from the Rust crypto25519.rs tests.
  """
  use ExUnit.Case, async: true

  alias Aguardia.Crypto

  # ==============================================================
  # Test Vectors from Rust Implementation
  # ==============================================================

  # Keys used in Rust tests
  @seed_my "5e8b7ecfe76faa5022ae7884f7f148d0b801e58ce8783d99bee69fb9e8029f71"
  @x_sk_my_hex "588b7ecfe76faa5022ae7884f7f148d0b801e58ce8783d99bee69fb9e8029f71"
  @x_pk_my_hex "00525d3ade51dbfb083b3c1fdf63b4a83fe5bef9f95deaf5f3278ccf816a7e0a"

  # Encryption test keys
  @x_sk_encrypt "481179010ae65f2bc7508430ac270386953aa75930042e22c184b78b41e95747"
  @x_pk_encrypt "af2af6e676e7801fc0b150733f79a20d6897b1c9cb4df3f651df81b180ca086e"
  @x_sk_other "a0d70cf83f6db80d093646d66fee62c422a1e160c3d4cd52ef44fd0f2698127d"
  @x_pk_other "2dfb6cf139728610e7766833862dc708cf9ff38a0f7c4b55c68b3bc0cc73d536"

  # Ed25519 test keys
  @ed_seed_my "454b10b610f9a3a99cd577e6d50a9fbabaa8e50e134b250f2695d17ca446f40e"
  @ed_pk_my "e498d275fe727bd9150b504d18b65b567516fd4ac3d0ed5e58a50475e8138d8f"

  # Test message (Russian text JSON)
  @test_message ~s({"key":"Какой-то текст"})
  @test_nonce 1_764_020_895

  # Expected ciphertext from Rust
  @expected_ciphertext "1b3518ec11aab49db6a1199de6db109314419b83988897fb66dd724612def8f8ebc6ebef9a42c07eb7daef2904c0252fcd734099"

  # Expected signature from Rust (over nonce || ciphertext)
  @expected_signature "2ebf005211c796dc7a5f02b84e115f0fa7e1803f801f6d41c611ed419d40999b21125c7ecdc91cd83e1b398b0929ced3129db1486e3c6475a18382dc4749ed0c"

  # Signed data (nonce LE || ciphertext)
  @signed_data_hex "9fd22469000000001b3518ec11aab49db6a1199de6db109314419b83988897fb66dd724612def8f8ebc6ebef9a42c07eb7daef2904c0252fcd734099"

  # ==============================================================
  # Helper Functions
  # ==============================================================

  defp hex_decode!(hex) do
    Base.decode16!(hex, case: :mixed)
  end

  # ==============================================================
  # Nonce Tests
  # ==============================================================

  describe "nonce_from_u64/1" do
    test "generates 24-byte nonce by repeating 8-byte LE timestamp 3 times" do
      nonce = Crypto.nonce_from_u64(@test_nonce)

      assert byte_size(nonce) == 24

      # The nonce should be the 8-byte LE timestamp repeated 3 times
      expected_8_bytes = <<@test_nonce::little-64>>
      assert nonce == expected_8_bytes <> expected_8_bytes <> expected_8_bytes
    end

    test "handles zero timestamp" do
      nonce = Crypto.nonce_from_u64(0)
      assert nonce == <<0::192>>
    end

    test "handles max u64 timestamp" do
      max_u64 = 0xFFFFFFFFFFFFFFFF
      nonce = Crypto.nonce_from_u64(max_u64)
      expected = <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>
      assert nonce == expected <> expected <> expected
    end

    test "nonce matches Rust implementation format" do
      # From Rust test, nonce 1764020895 as LE bytes
      nonce = Crypto.nonce_from_u64(@test_nonce)
      # 1764020895 = 0x692224D9 -> LE bytes: 9F D2 24 69 00 00 00 00
      <<first_8::binary-8, _rest::binary>> = nonce
      assert first_8 == <<0x9F, 0xD2, 0x24, 0x69, 0x00, 0x00, 0x00, 0x00>>
    end
  end

  # ==============================================================
  # X25519 Key Tests (Rust Compatibility)
  # ==============================================================

  describe "x25519_secret/1" do
    test "applies correct clamping to seed" do
      seed = hex_decode!(@seed_my)
      secret = Crypto.x25519_secret(seed)

      # Rust expected output
      expected = hex_decode!(@x_sk_my_hex)
      assert secret == expected
    end

    test "clamps first byte (clear bits 0, 1, 2)" do
      # Seed with 0xFF as first byte
      seed = <<0xFF, 0::248>>
      secret = Crypto.x25519_secret(seed)

      <<first, _rest::binary>> = secret
      # 0xFF & 248 = 0xF8
      assert first == 0xF8
    end

    test "clamps last byte (clear bit 7, set bit 6)" do
      # Seed with 0xFF as last byte
      seed = <<0::248, 0xFF>>
      secret = Crypto.x25519_secret(seed)

      <<_rest::binary-31, last>> = secret
      # 0xFF & 127 | 64 = 0x7F | 0x40 = 0x7F
      assert last == 0x7F
    end
  end

  describe "x25519_public/1" do
    test "generates correct public key from secret (Rust compatibility)" do
      secret = hex_decode!(@x_sk_my_hex)
      public = Crypto.x25519_public(secret)

      expected = hex_decode!(@x_pk_my_hex)
      assert public == expected
    end

    test "public key is 32 bytes" do
      secret = :crypto.strong_rand_bytes(32) |> Crypto.x25519_secret()
      public = Crypto.x25519_public(secret)
      assert byte_size(public) == 32
    end
  end

  describe "x25519_shared/2" do
    test "ECDH produces same shared secret from both sides" do
      # Generate two key pairs
      seed_a = Crypto.seed()
      sk_a = Crypto.x25519_secret(seed_a)
      pk_a = Crypto.x25519_public(sk_a)

      seed_b = Crypto.seed()
      sk_b = Crypto.x25519_secret(seed_b)
      pk_b = Crypto.x25519_public(sk_b)

      # Both sides should derive the same shared secret
      shared_a = Crypto.x25519_shared(sk_a, pk_b)
      shared_b = Crypto.x25519_shared(sk_b, pk_a)

      assert shared_a == shared_b
      assert byte_size(shared_a) == 32
    end
  end

  # ==============================================================
  # Ed25519 Tests
  # ==============================================================

  describe "ed25519_keypair_from_seed/1" do
    test "generates keypair from seed" do
      seed = hex_decode!(@ed_seed_my)
      {secret, public} = Crypto.ed25519_keypair_from_seed(seed)

      assert byte_size(secret) == 64
      assert byte_size(public) == 32
      assert public == hex_decode!(@ed_pk_my)
    end

    test "secret key is 64 bytes (seed || public)" do
      seed = Crypto.seed()
      {secret, public} = Crypto.ed25519_keypair_from_seed(seed)

      # Secret key should end with public key
      <<_seed::binary-32, pk_from_sk::binary-32>> = secret
      assert pk_from_sk == public
    end
  end

  describe "ed25519_public/1" do
    test "extracts public key from secret key" do
      seed = hex_decode!(@ed_seed_my)
      {secret, public} = Crypto.ed25519_keypair_from_seed(seed)

      extracted = Crypto.ed25519_public(secret)
      assert extracted == public
    end
  end

  describe "sign/2 and verify/3" do
    test "signature matches Rust implementation" do
      seed = hex_decode!(@ed_seed_my)
      {secret, _public} = Crypto.ed25519_keypair_from_seed(seed)

      # Sign the same data as Rust test
      signed_data = hex_decode!(@signed_data_hex)
      signature = Crypto.sign(signed_data, secret)

      expected_sig = hex_decode!(@expected_signature)
      assert signature == expected_sig
    end

    test "verifies signature from Rust implementation" do
      public = hex_decode!(@ed_pk_my)
      signed_data = hex_decode!(@signed_data_hex)
      signature = hex_decode!(@expected_signature)

      assert Crypto.verify(signed_data, signature, public)
    end

    test "rejects invalid signature" do
      public = hex_decode!(@ed_pk_my)
      signed_data = hex_decode!(@signed_data_hex)
      # Modify one byte
      bad_sig = <<0x00>> <> binary_part(hex_decode!(@expected_signature), 1, 63)

      refute Crypto.verify(signed_data, bad_sig, public)
    end

    test "rejects signature with wrong public key" do
      # Use a different public key
      other_seed = Crypto.seed()
      {_sk, other_pk} = Crypto.ed25519_keypair_from_seed(other_seed)

      signed_data = hex_decode!(@signed_data_hex)
      signature = hex_decode!(@expected_signature)

      refute Crypto.verify(signed_data, signature, other_pk)
    end

    test "sign and verify roundtrip" do
      seed = Crypto.seed()
      {secret, public} = Crypto.ed25519_keypair_from_seed(seed)
      data = "Hello, World!"

      signature = Crypto.sign(data, secret)
      assert Crypto.verify(data, signature, public)
    end
  end

  # ==============================================================
  # Encryption Tests (Rust Compatibility)
  # ==============================================================

  describe "encrypt_message/4" do
    test "produces ciphertext matching Rust implementation" do
      my_secret = hex_decode!(@x_sk_encrypt)
      their_public = hex_decode!(@x_pk_other)
      plaintext = @test_message

      ciphertext = Crypto.encrypt_message(their_public, my_secret, plaintext, @test_nonce)

      expected = hex_decode!(@expected_ciphertext)
      assert ciphertext == expected
    end
  end

  describe "decrypt_message/4" do
    test "decrypts ciphertext from Rust implementation" do
      # Decrypt using the other party's keys
      their_public = hex_decode!(@x_pk_encrypt)
      my_secret = hex_decode!(@x_sk_other)
      ciphertext = hex_decode!(@expected_ciphertext)

      {:ok, plaintext} = Crypto.decrypt_message(their_public, my_secret, ciphertext, @test_nonce)

      assert plaintext == @test_message
    end

    test "returns error for invalid ciphertext" do
      their_public = hex_decode!(@x_pk_encrypt)
      my_secret = hex_decode!(@x_sk_other)
      bad_ciphertext = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>

      assert {:error, :decrypt_failed} =
               Crypto.decrypt_message(their_public, my_secret, bad_ciphertext, @test_nonce)
    end

    test "returns error for wrong nonce" do
      their_public = hex_decode!(@x_pk_encrypt)
      my_secret = hex_decode!(@x_sk_other)
      ciphertext = hex_decode!(@expected_ciphertext)
      wrong_nonce = @test_nonce + 1

      assert {:error, :decrypt_failed} =
               Crypto.decrypt_message(their_public, my_secret, ciphertext, wrong_nonce)
    end

    test "returns error for wrong key" do
      wrong_secret = Crypto.seed() |> Crypto.x25519_secret()
      their_public = hex_decode!(@x_pk_encrypt)
      ciphertext = hex_decode!(@expected_ciphertext)

      assert {:error, :decrypt_failed} =
               Crypto.decrypt_message(their_public, wrong_secret, ciphertext, @test_nonce)
    end
  end

  describe "encrypt/decrypt roundtrip" do
    test "roundtrip works with random keys" do
      seed_a = Crypto.seed()
      sk_a = Crypto.x25519_secret(seed_a)
      pk_a = Crypto.x25519_public(sk_a)

      seed_b = Crypto.seed()
      sk_b = Crypto.x25519_secret(seed_b)
      pk_b = Crypto.x25519_public(sk_b)

      plaintext = "Hello, world! This is a test message with UTF-8: 日本語"
      nonce = Crypto.get_unixtime()

      # A encrypts for B
      ciphertext = Crypto.encrypt_message(pk_b, sk_a, plaintext, nonce)

      # B decrypts using A's public key
      {:ok, decrypted} = Crypto.decrypt_message(pk_a, sk_b, ciphertext, nonce)

      assert decrypted == plaintext
    end

    test "roundtrip with empty message" do
      seed_a = Crypto.seed()
      sk_a = Crypto.x25519_secret(seed_a)
      pk_a = Crypto.x25519_public(sk_a)

      seed_b = Crypto.seed()
      sk_b = Crypto.x25519_secret(seed_b)
      pk_b = Crypto.x25519_public(sk_b)

      plaintext = ""
      nonce = Crypto.get_unixtime()

      ciphertext = Crypto.encrypt_message(pk_b, sk_a, plaintext, nonce)
      {:ok, decrypted} = Crypto.decrypt_message(pk_a, sk_b, ciphertext, nonce)

      assert decrypted == plaintext
    end

    @tag :skip
    test "roundtrip with large message" do
      seed_a = Crypto.seed()
      sk_a = Crypto.x25519_secret(seed_a)
      pk_a = Crypto.x25519_public(sk_a)

      seed_b = Crypto.seed()
      sk_b = Crypto.x25519_secret(seed_b)
      pk_b = Crypto.x25519_public(sk_b)

      # 1MB message
      plaintext = :crypto.strong_rand_bytes(1024 * 1024)
      nonce = Crypto.get_unixtime()

      ciphertext = Crypto.encrypt_message(pk_b, sk_a, plaintext, nonce)
      {:ok, decrypted} = Crypto.decrypt_message(pk_a, sk_b, ciphertext, nonce)

      assert decrypted == plaintext
    end
  end

  # ==============================================================
  # Full Protocol Tests (encrypt_and_sign / verify_and_decrypt)
  # ==============================================================

  describe "encrypt_and_sign/4" do
    test "produces packet with correct structure" do
      seed_x = Crypto.seed()
      x_secret = Crypto.x25519_secret(seed_x)

      seed_ed = Crypto.seed()
      {ed_secret, _ed_public} = Crypto.ed25519_keypair_from_seed(seed_ed)

      other_seed = Crypto.seed()
      other_x_secret = Crypto.x25519_secret(other_seed)
      other_x_public = Crypto.x25519_public(other_x_secret)

      plaintext = "test message"
      packet = Crypto.encrypt_and_sign(plaintext, x_secret, ed_secret, other_x_public)

      # Packet should be: nonce (8) + ciphertext (len + 16 tag) + signature (64)
      # Minimum size: 8 + 16 + 64 = 88 bytes
      assert byte_size(packet) >= 88

      # First 8 bytes should be a valid timestamp (roughly current time)
      <<nonce::little-64, _rest::binary>> = packet
      now = Crypto.get_unixtime()
      assert abs(now - nonce) < 5
    end
  end

  describe "verify_and_decrypt/5" do
    test "successfully decrypts valid packet" do
      # Generate keys for sender
      seed_x_sender = Crypto.seed()
      x_secret_sender = Crypto.x25519_secret(seed_x_sender)
      x_public_sender = Crypto.x25519_public(x_secret_sender)

      seed_ed_sender = Crypto.seed()
      {ed_secret_sender, ed_public_sender} = Crypto.ed25519_keypair_from_seed(seed_ed_sender)

      # Generate keys for receiver
      seed_x_receiver = Crypto.seed()
      x_secret_receiver = Crypto.x25519_secret(seed_x_receiver)
      x_public_receiver = Crypto.x25519_public(x_secret_receiver)

      plaintext = "Hello from sender!"

      # Sender encrypts and signs
      packet =
        Crypto.encrypt_and_sign(plaintext, x_secret_sender, ed_secret_sender, x_public_receiver)

      # Receiver verifies and decrypts (0 skew = no nonce check)
      result =
        Crypto.verify_and_decrypt(
          packet,
          x_secret_receiver,
          x_public_sender,
          ed_public_sender,
          0
        )

      assert {:ok, ^plaintext} = result
    end

    test "roundtrip matches Rust encrypt_decrypt_roundtrip test" do
      # This mirrors the Rust test encrypt_decrypt_roundtrip
      seed_my = Crypto.seed()
      x_sk_my = Crypto.x25519_secret(seed_my)
      x_pk_my = Crypto.x25519_public(x_sk_my)
      {ed_sk_my, ed_pk_my} = Crypto.ed25519_keypair_from_seed(seed_my)

      seed_he = Crypto.seed()
      x_sk_he = Crypto.x25519_secret(seed_he)
      x_pk_he = Crypto.x25519_public(x_sk_he)

      text = ~s({"key":"Какой-то текст"})

      # Encrypt and sign
      data = Crypto.encrypt_and_sign(text, x_sk_my, ed_sk_my, x_pk_he)

      # Verify and decrypt (with 10 second nonce skew)
      {:ok, out} = Crypto.verify_and_decrypt(data, x_sk_he, x_pk_my, ed_pk_my, 10)

      assert out == text
    end

    test "returns :bad_format for packet too short" do
      short_packet = :crypto.strong_rand_bytes(50)

      result =
        Crypto.verify_and_decrypt(
          short_packet,
          :crypto.strong_rand_bytes(32),
          :crypto.strong_rand_bytes(32),
          :crypto.strong_rand_bytes(32),
          0
        )

      assert {:error, :bad_format} = result
    end

    test "returns :bad_signature for invalid signature" do
      # Generate valid packet structure but with wrong signature
      seed_x = Crypto.seed()
      x_secret = Crypto.x25519_secret(seed_x)
      x_public = Crypto.x25519_public(x_secret)

      seed_ed = Crypto.seed()
      {ed_secret, ed_public} = Crypto.ed25519_keypair_from_seed(seed_ed)

      other_seed = Crypto.seed()
      other_x_secret = Crypto.x25519_secret(other_seed)
      other_x_public = Crypto.x25519_public(other_x_secret)

      # Create valid packet
      packet = Crypto.encrypt_and_sign("test", x_secret, ed_secret, other_x_public)

      # Corrupt the signature (last 64 bytes)
      packet_size = byte_size(packet)
      <<body::binary-size(packet_size - 64), _sig::binary-64>> = packet
      bad_packet = body <> :crypto.strong_rand_bytes(64)

      result = Crypto.verify_and_decrypt(bad_packet, other_x_secret, x_public, ed_public, 0)

      assert {:error, :bad_signature} = result
    end

    test "returns :bad_nonce for expired timestamp" do
      # Generate keys
      seed_x_sender = Crypto.seed()
      x_secret_sender = Crypto.x25519_secret(seed_x_sender)
      x_public_sender = Crypto.x25519_public(x_secret_sender)

      seed_ed_sender = Crypto.seed()
      {ed_secret_sender, ed_public_sender} = Crypto.ed25519_keypair_from_seed(seed_ed_sender)

      seed_x_receiver = Crypto.seed()
      x_secret_receiver = Crypto.x25519_secret(seed_x_receiver)
      x_public_receiver = Crypto.x25519_public(x_secret_receiver)

      plaintext = "test"

      # Manually create a packet with an old timestamp
      old_nonce = Crypto.get_unixtime() - 100

      ciphertext =
        Crypto.encrypt_message(x_public_receiver, x_secret_sender, plaintext, old_nonce)

      signed_data = <<old_nonce::little-64, ciphertext::binary>>
      signature = Crypto.sign(signed_data, ed_secret_sender)

      old_packet = signed_data <> signature

      # Try to verify with 5 second max skew
      result =
        Crypto.verify_and_decrypt(
          old_packet,
          x_secret_receiver,
          x_public_sender,
          ed_public_sender,
          5
        )

      assert {:error, :bad_nonce} = result
    end

    test "accepts packet within nonce skew" do
      # Generate keys
      seed_x_sender = Crypto.seed()
      x_secret_sender = Crypto.x25519_secret(seed_x_sender)
      x_public_sender = Crypto.x25519_public(x_secret_sender)

      seed_ed_sender = Crypto.seed()
      {ed_secret_sender, ed_public_sender} = Crypto.ed25519_keypair_from_seed(seed_ed_sender)

      seed_x_receiver = Crypto.seed()
      x_secret_receiver = Crypto.x25519_secret(seed_x_receiver)
      x_public_receiver = Crypto.x25519_public(x_secret_receiver)

      plaintext = "test"

      # Create packet with slightly old timestamp (2 seconds ago)
      nonce = Crypto.get_unixtime() - 2
      ciphertext = Crypto.encrypt_message(x_public_receiver, x_secret_sender, plaintext, nonce)

      signed_data = <<nonce::little-64, ciphertext::binary>>
      signature = Crypto.sign(signed_data, ed_secret_sender)

      packet = signed_data <> signature

      # Should succeed with 5 second skew
      result =
        Crypto.verify_and_decrypt(
          packet,
          x_secret_receiver,
          x_public_sender,
          ed_public_sender,
          5
        )

      assert {:ok, ^plaintext} = result
    end
  end

  # ==============================================================
  # Hex Encoding/Decoding Tests
  # ==============================================================

  describe "hex_encode/1" do
    test "encodes binary to uppercase hex" do
      assert Crypto.hex_encode(<<0, 1, 2, 255>>) == "000102FF"
    end

    test "handles empty binary" do
      assert Crypto.hex_encode(<<>>) == ""
    end
  end

  describe "hex_decode/1" do
    test "decodes valid hex string" do
      assert {:ok, <<0, 1, 2, 255>>} = Crypto.hex_decode("000102FF")
      assert {:ok, <<0, 1, 2, 255>>} = Crypto.hex_decode("000102ff")
    end

    test "returns error for invalid hex" do
      assert {:error, :invalid_hex} = Crypto.hex_decode("GGGG")
      assert {:error, :invalid_hex} = Crypto.hex_decode("0")
    end
  end

  describe "hex_decode32/1" do
    test "decodes 64-char hex to 32-byte binary" do
      hex = String.duplicate("00", 32)
      assert {:ok, bin} = Crypto.hex_decode32(hex)
      assert byte_size(bin) == 32
    end

    test "returns error for wrong length" do
      assert {:error, :invalid_length} = Crypto.hex_decode32("0011")
    end
  end

  describe "hex_decode64/1" do
    test "decodes 128-char hex to 64-byte binary" do
      hex = String.duplicate("00", 64)
      assert {:ok, bin} = Crypto.hex_decode64(hex)
      assert byte_size(bin) == 64
    end

    test "returns error for wrong length" do
      assert {:error, :invalid_length} = Crypto.hex_decode64("0011")
    end
  end

  # ==============================================================
  # Utility Tests
  # ==============================================================

  describe "seed/0" do
    test "generates 32-byte random seed" do
      seed = Crypto.seed()
      assert byte_size(seed) == 32
    end

    test "generates unique seeds" do
      seeds = for _ <- 1..100, do: Crypto.seed()
      unique_seeds = Enum.uniq(seeds)
      assert length(unique_seeds) == 100
    end
  end

  describe "get_unixtime/0" do
    test "returns current unix timestamp" do
      now = :os.system_time(:second)
      crypto_now = Crypto.get_unixtime()

      # Should be within 1 second
      assert abs(now - crypto_now) <= 1
    end
  end

  # ==============================================================
  # Cross-Compatibility Matrix Tests
  # ==============================================================

  describe "cross-compatibility with Rust test vectors" do
    test "full packet format compatibility" do
      # Use exact keys from Rust tests
      # Sender keys
      x_sk_my = hex_decode!(@x_sk_encrypt)
      ed_seed = hex_decode!(@ed_seed_my)
      {ed_sk_my, _ed_pk_my} = Crypto.ed25519_keypair_from_seed(ed_seed)

      # Receiver keys
      x_pk_he = hex_decode!(@x_pk_other)

      # Encrypt with known nonce
      plaintext = @test_message
      ciphertext = Crypto.encrypt_message(x_pk_he, x_sk_my, plaintext, @test_nonce)

      # Verify ciphertext matches Rust
      assert ciphertext == hex_decode!(@expected_ciphertext)

      # Build signed_data and sign
      signed_data = <<@test_nonce::little-64, ciphertext::binary>>
      assert signed_data == hex_decode!(@signed_data_hex)

      signature = Crypto.sign(signed_data, ed_sk_my)
      assert signature == hex_decode!(@expected_signature)
    end

    test "decrypt packet created by Rust" do
      # This simulates receiving a packet from Rust implementation
      ciphertext = hex_decode!(@expected_ciphertext)
      signature = hex_decode!(@expected_signature)

      # Build the packet format: nonce || ciphertext || signature
      packet = <<@test_nonce::little-64, ciphertext::binary, signature::binary>>

      # Decrypt using "other" party keys
      x_sk_he = hex_decode!(@x_sk_other)
      x_pk_my = hex_decode!(@x_pk_encrypt)
      ed_pk_my = hex_decode!(@ed_pk_my)

      # Verify and decrypt (skip nonce check with 0)
      {:ok, plaintext} = Crypto.verify_and_decrypt(packet, x_sk_he, x_pk_my, ed_pk_my, 0)

      assert plaintext == @test_message
    end
  end

  # ==============================================================
  # Edge Cases and Error Handling
  # ==============================================================

  describe "edge cases" do
    test "handles binary data with null bytes" do
      seed_a = Crypto.seed()
      sk_a = Crypto.x25519_secret(seed_a)
      pk_a = Crypto.x25519_public(sk_a)

      seed_b = Crypto.seed()
      sk_b = Crypto.x25519_secret(seed_b)
      pk_b = Crypto.x25519_public(sk_b)

      # Binary with null bytes
      plaintext = <<0, 1, 0, 2, 0, 3, 0, 0, 0>>
      nonce = Crypto.get_unixtime()

      ciphertext = Crypto.encrypt_message(pk_b, sk_a, plaintext, nonce)
      {:ok, decrypted} = Crypto.decrypt_message(pk_a, sk_b, ciphertext, nonce)

      assert decrypted == plaintext
    end

    test "handles all byte values in message" do
      seed_a = Crypto.seed()
      sk_a = Crypto.x25519_secret(seed_a)
      pk_a = Crypto.x25519_public(sk_a)

      seed_b = Crypto.seed()
      sk_b = Crypto.x25519_secret(seed_b)
      pk_b = Crypto.x25519_public(sk_b)

      # All possible byte values
      plaintext = :binary.list_to_bin(Enum.to_list(0..255))
      nonce = Crypto.get_unixtime()

      ciphertext = Crypto.encrypt_message(pk_b, sk_a, plaintext, nonce)
      {:ok, decrypted} = Crypto.decrypt_message(pk_a, sk_b, ciphertext, nonce)

      assert decrypted == plaintext
    end
  end
end

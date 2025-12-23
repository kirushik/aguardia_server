defmodule Aguardia.Crypto do
  @moduledoc """
  Cryptographic operations for the Aguardia protocol.

  Implements:
  - X25519 ECDH key exchange
  - XChaCha20-Poly1305 AEAD encryption
  - Ed25519 signatures

  Critical: The nonce derivation must match the Rust implementation exactly:
  24-byte nonce is created by repeating 8-byte little-endian timestamp 3 times.

  This module uses the `libsodium` port driver for crypto operations.
  """

  @doc """
  Generate a random 32-byte seed.
  """
  @spec seed() :: binary()
  def seed do
    :crypto.strong_rand_bytes(32)
  end

  @doc """
  Get current Unix timestamp.
  """
  @spec get_unixtime() :: non_neg_integer()
  def get_unixtime do
    System.system_time(:second)
  end

  @doc """
  Convert a u64 timestamp to a 24-byte XChaCha20 nonce.

  The Rust implementation repeats the 8-byte LE timestamp 3 times.
  """
  @spec nonce_from_u64(non_neg_integer()) :: binary()
  def nonce_from_u64(n) when is_integer(n) do
    bytes = <<n::little-64>>
    bytes <> bytes <> bytes
  end

  # ============================================================
  # X25519 Key Operations
  # ============================================================

  @doc """
  Derive X25519 secret key from a 32-byte seed.

  Applies the standard clamping:
  - Clear bits 0, 1, 2 of first byte
  - Clear bit 7 of last byte
  - Set bit 6 of last byte
  """
  @spec x25519_secret(binary()) :: binary()
  def x25519_secret(<<first::8, rest::binary-30, last::8>>) do
    first = Bitwise.band(first, 248)
    last = last |> Bitwise.band(127) |> Bitwise.bor(64)
    <<first::8, rest::binary, last::8>>
  end

  @doc """
  Compute X25519 public key from secret key.
  """
  @spec x25519_public(binary()) :: binary()
  def x25519_public(secret) when byte_size(secret) == 32 do
    :libsodium_crypto_scalarmult_curve25519.base(secret)
  end

  @doc """
  Compute X25519 shared secret (ECDH).
  """
  @spec x25519_shared(binary(), binary()) :: binary()
  def x25519_shared(my_secret, their_public)
      when byte_size(my_secret) == 32 and byte_size(their_public) == 32 do
    :libsodium_crypto_scalarmult_curve25519.crypto_scalarmult_curve25519(my_secret, their_public)
  end

  # ============================================================
  # Ed25519 Key Operations
  # ============================================================

  @doc """
  Derive Ed25519 signing key from a 32-byte seed.
  Returns {secret_key, public_key} where secret_key is 64 bytes (seed || public).
  """
  @spec ed25519_keypair_from_seed(binary()) :: {binary(), binary()}
  def ed25519_keypair_from_seed(seed) when byte_size(seed) == 32 do
    {public, secret} = :libsodium_crypto_sign_ed25519.seed_keypair(seed)
    {secret, public}
  end

  @doc """
  Get Ed25519 public key from secret key (64 bytes).
  The public key is the last 32 bytes of the secret key.
  """
  @spec ed25519_public(binary()) :: binary()
  def ed25519_public(secret_key) when byte_size(secret_key) == 64 do
    <<_seed::binary-32, public::binary-32>> = secret_key
    public
  end

  @doc """
  Sign data with Ed25519.
  """
  @spec sign(binary(), binary()) :: binary()
  def sign(data, secret_key) when byte_size(secret_key) == 64 do
    :libsodium_crypto_sign_ed25519.detached(data, secret_key)
  end

  @doc """
  Verify Ed25519 signature.
  """
  @spec verify(binary(), binary(), binary()) :: boolean()
  def verify(data, signature, public_key)
      when byte_size(signature) == 64 and byte_size(public_key) == 32 do
    case :libsodium_crypto_sign_ed25519.verify_detached(signature, data, public_key) do
      0 -> true
      _ -> false
    end
  end

  # ============================================================
  # Encryption / Decryption
  # ============================================================

  @doc """
  Encrypt a message using XChaCha20-Poly1305.
  """
  @spec encrypt_message(binary(), binary(), binary(), non_neg_integer()) :: binary()
  def encrypt_message(their_public, my_secret, plaintext, nonce) do
    shared = x25519_shared(my_secret, their_public)
    nonce_bytes = nonce_from_u64(nonce)
    # AEAD with empty associated data
    :libsodium_crypto_aead_xchacha20poly1305.ietf_encrypt(plaintext, <<>>, nonce_bytes, shared)
  end

  @doc """
  Decrypt a message using XChaCha20-Poly1305.
  Returns {:ok, plaintext} or {:error, :decrypt_failed}.
  """
  @spec decrypt_message(binary(), binary(), binary(), non_neg_integer()) ::
          {:ok, binary()} | {:error, :decrypt_failed}
  def decrypt_message(their_public, my_secret, ciphertext, nonce) do
    shared = x25519_shared(my_secret, their_public)
    nonce_bytes = nonce_from_u64(nonce)

    try do
      result =
        :libsodium_crypto_aead_xchacha20poly1305.ietf_decrypt(
          ciphertext,
          <<>>,
          nonce_bytes,
          shared
        )

      # libsodium returns -1 on decryption failure instead of raising
      case result do
        -1 -> {:error, :decrypt_failed}
        plaintext when is_binary(plaintext) -> {:ok, plaintext}
        _ -> {:error, :decrypt_failed}
      end
    rescue
      _ -> {:error, :decrypt_failed}
    catch
      :error, _ -> {:error, :decrypt_failed}
      :exit, _ -> {:error, :decrypt_failed}
    end
  end

  @doc """
  Encrypt and sign a message.

  Returns: <<nonce::64, ciphertext::binary, signature::64>>
  """
  @spec encrypt_and_sign(binary(), binary(), binary(), binary()) :: binary()
  def encrypt_and_sign(plaintext, x_my_secret, ed_my_secret, x_their_public) do
    nonce = get_unixtime()
    ciphertext = encrypt_message(x_their_public, x_my_secret, plaintext, nonce)

    # Create data to sign: nonce || ciphertext
    signed_data = <<nonce::little-64, ciphertext::binary>>
    signature = sign(signed_data, ed_my_secret)

    # Return: nonce || ciphertext || signature
    <<nonce::little-64, ciphertext::binary, signature::binary>>
  end

  @doc """
  Verify signature and decrypt a message.

  Input format: <<nonce::64, ciphertext::binary, signature::64>>

  Returns:
  - {:ok, plaintext} on success
  - {:error, :bad_format} if packet too short
  - {:error, :bad_signature} if signature verification fails
  - {:error, :bad_nonce} if nonce is too far from current time
  - {:error, :decrypt_failed} if decryption fails
  """
  @spec verify_and_decrypt(binary(), binary(), binary(), binary(), non_neg_integer()) ::
          {:ok, binary()}
          | {:error, :bad_format | :bad_signature | :bad_nonce | :decrypt_failed}
  def verify_and_decrypt(packet, x_my_secret, x_their_public, ed_their_public, max_nonce_skew) do
    # Minimum: 8 (nonce) + 16 (poly1305 tag minimum) + 64 (signature) = 88 bytes
    # But we allow smaller ciphertext, so minimum is 8 + 64 = 72
    if byte_size(packet) < 72 do
      {:error, :bad_format}
    else
      sig_start = byte_size(packet) - 64
      <<nonce_and_cipher::binary-size(sig_start), signature::binary-64>> = packet

      if byte_size(nonce_and_cipher) < 8 do
        {:error, :bad_format}
      else
        <<nonce::little-64, ciphertext::binary>> = nonce_and_cipher

        # Verify signature over nonce || ciphertext
        if not verify(nonce_and_cipher, signature, ed_their_public) do
          {:error, :bad_signature}
        else
          # Check nonce (timestamp) is within acceptable range
          if max_nonce_skew > 0 do
            now = get_unixtime()

            if abs(now - nonce) > max_nonce_skew do
              {:error, :bad_nonce}
            else
              decrypt_message(x_their_public, x_my_secret, ciphertext, nonce)
            end
          else
            decrypt_message(x_their_public, x_my_secret, ciphertext, nonce)
          end
        end
      end
    end
  end

  # ============================================================
  # Hex Encoding / Decoding Helpers
  # ============================================================

  @doc """
  Decode hex string to binary, returning {:ok, binary} or {:error, :invalid_hex}.
  """
  @spec hex_decode(String.t()) :: {:ok, binary()} | {:error, :invalid_hex}
  def hex_decode(hex) when is_binary(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, :invalid_hex}
    end
  end

  @doc """
  Decode hex string to 32-byte binary.
  """
  @spec hex_decode32(String.t()) :: {:ok, binary()} | {:error, :invalid_hex | :invalid_length}
  def hex_decode32(hex) when is_binary(hex) do
    case hex_decode(hex) do
      {:ok, bin} when byte_size(bin) == 32 -> {:ok, bin}
      {:ok, _} -> {:error, :invalid_length}
      error -> error
    end
  end

  @doc """
  Decode hex string to 64-byte binary (for signatures).
  """
  @spec hex_decode64(String.t()) :: {:ok, binary()} | {:error, :invalid_hex | :invalid_length}
  def hex_decode64(hex) when is_binary(hex) do
    case hex_decode(hex) do
      {:ok, bin} when byte_size(bin) == 64 -> {:ok, bin}
      {:ok, _} -> {:error, :invalid_length}
      error -> error
    end
  end

  @doc """
  Encode binary to uppercase hex string.
  """
  @spec hex_encode(binary()) :: String.t()
  def hex_encode(bin) when is_binary(bin) do
    Base.encode16(bin, case: :upper)
  end
end

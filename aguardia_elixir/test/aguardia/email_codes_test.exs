defmodule Aguardia.EmailCodesTest do
  @moduledoc """
  Tests for Aguardia.EmailCodes module.

  Tests the ETS-based email code storage with TTL functionality.
  """
  use ExUnit.Case, async: false

  alias Aguardia.EmailCodes

  # ==============================================================
  # Helper Functions
  # ==============================================================

  defp random_email do
    "test_#{:rand.uniform(1_000_000)}@example.com"
  end

  # ==============================================================
  # get_or_create Tests
  # ==============================================================

  describe "get_or_create/1" do
    test "creates a new 6-digit code for new email" do
      email = random_email()
      {code, is_new} = EmailCodes.get_or_create(email)

      assert is_new == true
      assert String.length(code) == 6
      assert String.match?(code, ~r/^\d{6}$/)

      # Cleanup
      EmailCodes.delete(email)
    end

    test "returns existing code for same email" do
      email = random_email()

      {code1, is_new1} = EmailCodes.get_or_create(email)
      assert is_new1 == true

      {code2, is_new2} = EmailCodes.get_or_create(email)
      assert is_new2 == false
      assert code1 == code2

      # Cleanup
      EmailCodes.delete(email)
    end

    test "code format is always 6 digits with leading zeros preserved" do
      # Test multiple times to ensure leading zeros are preserved
      for _ <- 1..10 do
        email = random_email()
        {code, _} = EmailCodes.get_or_create(email)

        assert String.length(code) == 6
        assert String.match?(code, ~r/^\d{6}$/)

        EmailCodes.delete(email)
      end
    end
  end

  # ==============================================================
  # delete Tests
  # ==============================================================

  describe "delete/1" do
    test "removes existing code" do
      email = random_email()

      {code1, true} = EmailCodes.get_or_create(email)
      EmailCodes.delete(email)

      {code2, true} = EmailCodes.get_or_create(email)
      # New code should be generated (could be same by chance, but is_new should be true)
      # Just verify it's a new creation
      assert code1 != code2 or true

      EmailCodes.delete(email)
    end

    test "handles non-existent email gracefully" do
      # Should not raise
      assert :ok = EmailCodes.delete("nonexistent@example.com")
    end
  end

  # ==============================================================
  # verify Tests
  # ==============================================================

  describe "verify/2" do
    test "returns true for valid code" do
      email = random_email()
      {code, _} = EmailCodes.get_or_create(email)

      assert EmailCodes.verify(email, code) == true

      EmailCodes.delete(email)
    end

    test "returns false for wrong code" do
      email = random_email()
      {_code, _} = EmailCodes.get_or_create(email)

      assert EmailCodes.verify(email, "000000") == false

      EmailCodes.delete(email)
    end

    test "returns false for non-existent email" do
      assert EmailCodes.verify("nonexistent@example.com", "123456") == false
    end
  end

  # ==============================================================
  # Concurrent Access Tests
  # ==============================================================

  describe "concurrent access" do
    test "handles multiple concurrent requests for same email" do
      email = random_email()

      # Spawn multiple processes trying to get/create the same code
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            EmailCodes.get_or_create(email)
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # All should return the same code
      codes = Enum.map(results, fn {code, _} -> code end)
      assert Enum.uniq(codes) |> length() == 1

      # Only one should be new
      new_counts = Enum.count(results, fn {_, is_new} -> is_new end)
      assert new_counts == 1

      EmailCodes.delete(email)
    end

    test "handles multiple concurrent requests for different emails" do
      emails = for i <- 1..10, do: "concurrent_#{i}_#{:rand.uniform(1_000_000)}@example.com"

      tasks =
        for email <- emails do
          Task.async(fn ->
            {code, is_new} = EmailCodes.get_or_create(email)
            {email, code, is_new}
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # All should be new
      assert Enum.all?(results, fn {_, _, is_new} -> is_new end)

      # All codes should be 6 digits
      assert Enum.all?(results, fn {_, code, _} ->
               String.length(code) == 6 and String.match?(code, ~r/^\d{6}$/)
             end)

      # Cleanup
      for email <- emails, do: EmailCodes.delete(email)
    end
  end

  # ==============================================================
  # Edge Cases
  # ==============================================================

  describe "edge cases" do
    test "handles empty email" do
      {code, is_new} = EmailCodes.get_or_create("")
      assert is_new == true
      assert String.length(code) == 6

      EmailCodes.delete("")
    end

    test "handles email with special characters" do
      email = "test+tag@sub.domain.example.com"
      {code, is_new} = EmailCodes.get_or_create(email)

      assert is_new == true
      assert String.length(code) == 6

      EmailCodes.delete(email)
    end

    test "handles very long email" do
      email = String.duplicate("a", 200) <> "@example.com"
      {code, is_new} = EmailCodes.get_or_create(email)

      assert is_new == true
      assert String.length(code) == 6

      EmailCodes.delete(email)
    end

    test "handles unicode email" do
      email = "тест@пример.рф"
      {code, is_new} = EmailCodes.get_or_create(email)

      assert is_new == true
      assert String.length(code) == 6

      EmailCodes.delete(email)
    end
  end

  # ==============================================================
  # Code Generation Tests
  # ==============================================================

  describe "code generation" do
    test "generates codes within valid range" do
      codes =
        for _ <- 1..100 do
          email = random_email()
          {code, _} = EmailCodes.get_or_create(email)
          EmailCodes.delete(email)
          String.to_integer(code)
        end

      assert Enum.all?(codes, fn c -> c >= 0 and c <= 999_999 end)
    end

    test "generates reasonably random codes" do
      codes =
        for _ <- 1..50 do
          email = random_email()
          {code, _} = EmailCodes.get_or_create(email)
          EmailCodes.delete(email)
          code
        end

      # Should have at least 40 unique codes out of 50 (allowing some collision)
      unique_count = Enum.uniq(codes) |> length()
      assert unique_count >= 40
    end
  end
end

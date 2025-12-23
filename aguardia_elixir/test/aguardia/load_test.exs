defmodule Aguardia.LoadTest do
  @moduledoc """
  Load tests for the Aguardia server.

  These tests verify that the server can handle large numbers of
  concurrent connections without lock contention or performance degradation.
  """
  use ExUnit.Case, async: false

  alias Aguardia.Crypto
  alias Aguardia.ServerState
  alias AguardiaWeb.Commands

  # ==============================================================
  # Configuration
  # ==============================================================

  # Number of simulated sessions for load tests
  @session_count 1_000
  # Timeout for load test operations
  @timeout 30_000

  # ==============================================================
  # Helper Functions
  # ==============================================================

  defp generate_user_keys do
    seed_x = Crypto.seed()
    x_secret = Crypto.x25519_secret(seed_x)
    x_public = Crypto.x25519_public(x_secret)

    seed_ed = Crypto.seed()
    {ed_secret, ed_public} = Crypto.ed25519_keypair_from_seed(seed_ed)

    %{
      x_secret: x_secret,
      x_public: x_public,
      ed_secret: ed_secret,
      ed_public: ed_public
    }
  end

  defp simulate_session(user_id, keys) do
    # Register in session registry
    Registry.register(Aguardia.SessionRegistry, user_id, %{
      x: keys.x_public,
      ed: keys.ed_public
    })

    # Simulate some activity
    for _ <- 1..10 do
      json = Jason.encode!(%{action: "status"})
      {:ok, true} = Commands.handle(user_id, json)

      json = Jason.encode!(%{action: "my_id"})
      {:ok, ^user_id} = Commands.handle(user_id, json)
    end

    # Unregister
    Registry.unregister(Aguardia.SessionRegistry, user_id)

    :ok
  end

  # ==============================================================
  # Registry Concurrency Tests
  # ==============================================================

  describe "registry concurrency" do
    @tag timeout: @timeout
    test "handles many concurrent registrations" do
      # Generate keys for all users upfront
      users =
        for i <- 1..@session_count do
          {i + 100_000, generate_user_keys()}
        end

      # Register all concurrently
      tasks =
        for {user_id, keys} <- users do
          Task.async(fn ->
            Registry.register(Aguardia.SessionRegistry, user_id, %{
              x: keys.x_public,
              ed: keys.ed_public
            })

            user_id
          end)
        end

      # Wait for all registrations
      registered = Enum.map(tasks, fn task -> Task.await(task, @timeout) end)

      assert length(registered) == @session_count

      # Verify all are registered
      for {user_id, keys} <- users do
        case Registry.lookup(Aguardia.SessionRegistry, user_id) do
          [{_pid, meta}] ->
            assert meta.x == keys.x_public
            assert meta.ed == keys.ed_public

          [] ->
            flunk("User #{user_id} not found in registry")
        end
      end

      # Cleanup
      for {user_id, _keys} <- users do
        Registry.unregister(Aguardia.SessionRegistry, user_id)
      end
    end

    @tag timeout: @timeout
    test "handles concurrent lookups under load" do
      # Pre-register some users
      users =
        for i <- 1..100 do
          user_id = i + 200_000
          keys = generate_user_keys()

          Registry.register(Aguardia.SessionRegistry, user_id, %{
            x: keys.x_public,
            ed: keys.ed_public
          })

          {user_id, keys}
        end

      # Perform many concurrent lookups
      tasks =
        for _ <- 1..@session_count do
          Task.async(fn ->
            {user_id, keys} = Enum.random(users)

            case Registry.lookup(Aguardia.SessionRegistry, user_id) do
              [{_pid, meta}] ->
                assert meta.x == keys.x_public
                :found

              [] ->
                :not_found
            end
          end)
        end

      results = Enum.map(tasks, fn task -> Task.await(task, @timeout) end)

      # All lookups should succeed
      assert Enum.all?(results, fn r -> r == :found end)

      # Cleanup
      for {user_id, _keys} <- users do
        Registry.unregister(Aguardia.SessionRegistry, user_id)
      end
    end
  end

  # ==============================================================
  # Command Processing Load Tests
  # ==============================================================

  describe "command processing load" do
    @tag timeout: @timeout
    test "handles many concurrent status commands" do
      tasks =
        for i <- 1..@session_count do
          Task.async(fn ->
            user_id = i + 300_000
            json = Jason.encode!(%{action: "status"})
            Commands.handle(user_id, json)
          end)
        end

      results = Enum.map(tasks, fn task -> Task.await(task, @timeout) end)

      # All should succeed
      success_count = Enum.count(results, fn r -> r == {:ok, true} end)
      assert success_count == @session_count
    end

    @tag timeout: @timeout
    test "handles many concurrent my_id commands" do
      tasks =
        for i <- 1..@session_count do
          Task.async(fn ->
            user_id = i + 400_000
            json = Jason.encode!(%{action: "my_id"})
            {result, returned_id} = Commands.handle(user_id, json)
            {result, returned_id == user_id}
          end)
        end

      results = Enum.map(tasks, fn task -> Task.await(task, @timeout) end)

      # All should succeed with correct ID
      correct_count = Enum.count(results, fn {result, correct} -> result == :ok and correct end)
      assert correct_count == @session_count
    end

    @tag timeout: @timeout
    test "handles mixed concurrent commands" do
      commands = [
        %{action: "status"},
        %{action: "my_id"},
        %{action: "get_id", x: String.duplicate("00", 32), ed: String.duplicate("11", 32)}
      ]

      tasks =
        for i <- 1..@session_count do
          Task.async(fn ->
            user_id = i + 500_000
            cmd = Enum.random(commands)
            json = Jason.encode!(cmd)

            case Commands.handle(user_id, json) do
              {:ok, _} -> :ok
              {:error, _} -> :error
            end
          end)
        end

      results = Enum.map(tasks, fn task -> Task.await(task, @timeout) end)

      # Count results
      ok_count = Enum.count(results, fn r -> r == :ok end)
      error_count = Enum.count(results, fn r -> r == :error end)

      # All should complete (ok or expected error)
      assert ok_count + error_count == @session_count
    end
  end

  # ==============================================================
  # Simulated Session Tests
  # ==============================================================

  describe "simulated sessions" do
    @tag timeout: @timeout
    test "handles many concurrent full session simulations" do
      tasks =
        for i <- 1..500 do
          Task.async(fn ->
            user_id = i + 600_000
            keys = generate_user_keys()
            simulate_session(user_id, keys)
          end)
        end

      results = Enum.map(tasks, fn task -> Task.await(task, @timeout) end)

      # All should succeed
      assert Enum.all?(results, fn r -> r == :ok end)
    end
  end

  # ==============================================================
  # Crypto Performance Tests
  # ==============================================================

  describe "crypto performance" do
    @tag timeout: @timeout
    test "key generation throughput" do
      start_time = System.monotonic_time(:millisecond)

      keys =
        for _ <- 1..1000 do
          generate_user_keys()
        end

      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      assert length(keys) == 1000
      # Should complete in reasonable time (< 5 seconds)
      assert duration_ms < 5000

      IO.puts("\nKey generation: 1000 keypairs in #{duration_ms}ms")
    end

    @tag timeout: @timeout
    test "encryption throughput" do
      sender_keys = generate_user_keys()
      receiver_keys = generate_user_keys()
      plaintext = "Test message for encryption throughput"

      start_time = System.monotonic_time(:millisecond)

      _packets =
        for _ <- 1..1000 do
          Crypto.encrypt_and_sign(
            plaintext,
            sender_keys.x_secret,
            sender_keys.ed_secret,
            receiver_keys.x_public
          )
        end

      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      # Should complete in reasonable time (< 5 seconds)
      assert duration_ms < 5000

      IO.puts("\nEncryption: 1000 packets in #{duration_ms}ms")
    end

    @tag timeout: @timeout
    test "decryption throughput" do
      sender_keys = generate_user_keys()
      receiver_keys = generate_user_keys()
      plaintext = "Test message for decryption throughput"

      # Create packets
      packets =
        for _ <- 1..1000 do
          Crypto.encrypt_and_sign(
            plaintext,
            sender_keys.x_secret,
            sender_keys.ed_secret,
            receiver_keys.x_public
          )
        end

      start_time = System.monotonic_time(:millisecond)

      results =
        for packet <- packets do
          Crypto.verify_and_decrypt(
            packet,
            receiver_keys.x_secret,
            sender_keys.x_public,
            sender_keys.ed_public,
            0
          )
        end

      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      # All should succeed
      assert Enum.all?(results, fn {status, _} -> status == :ok end)

      # Should complete in reasonable time (< 10 seconds)
      assert duration_ms < 10000

      IO.puts("\nDecryption: 1000 packets in #{duration_ms}ms")
    end

    @tag timeout: @timeout
    test "concurrent encrypt/decrypt" do
      sender_keys = generate_user_keys()
      receiver_keys = generate_user_keys()
      plaintext = "Concurrent test message"

      start_time = System.monotonic_time(:millisecond)

      tasks =
        for _ <- 1..500 do
          Task.async(fn ->
            # Encrypt
            packet =
              Crypto.encrypt_and_sign(
                plaintext,
                sender_keys.x_secret,
                sender_keys.ed_secret,
                receiver_keys.x_public
              )

            # Decrypt
            {:ok, decrypted} =
              Crypto.verify_and_decrypt(
                packet,
                receiver_keys.x_secret,
                sender_keys.x_public,
                sender_keys.ed_public,
                0
              )

            decrypted == plaintext
          end)
        end

      results = Enum.map(tasks, fn task -> Task.await(task, @timeout) end)

      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      # All should succeed
      assert Enum.all?(results)

      IO.puts("\nConcurrent encrypt/decrypt: 500 roundtrips in #{duration_ms}ms")
    end
  end

  # ==============================================================
  # Memory Usage Tests
  # ==============================================================

  describe "memory usage" do
    @tag timeout: @timeout
    test "registry does not leak memory on register/unregister cycles" do
      # Get initial memory
      :erlang.garbage_collect()
      initial_memory = :erlang.memory(:total)

      # Perform many register/unregister cycles
      for _ <- 1..10 do
        users =
          for i <- 1..1000 do
            user_id = i + 700_000 + :rand.uniform(100_000)
            keys = generate_user_keys()

            Registry.register(Aguardia.SessionRegistry, user_id, %{
              x: keys.x_public,
              ed: keys.ed_public
            })

            user_id
          end

        # Small delay
        Process.sleep(10)

        # Unregister all
        for user_id <- users do
          Registry.unregister(Aguardia.SessionRegistry, user_id)
        end
      end

      # Force garbage collection
      :erlang.garbage_collect()
      Process.sleep(100)
      :erlang.garbage_collect()

      final_memory = :erlang.memory(:total)

      # Memory growth should be reasonable (allow 50MB growth for test overhead)
      memory_growth = final_memory - initial_memory
      max_allowed_growth = 50 * 1024 * 1024

      IO.puts("\nMemory growth after register/unregister cycles: #{div(memory_growth, 1024)}KB")

      assert memory_growth < max_allowed_growth,
             "Memory grew by #{div(memory_growth, 1024 * 1024)}MB, expected less than 50MB"
    end
  end

  # ==============================================================
  # Heartbeat Simulation Tests
  # ==============================================================

  describe "heartbeat simulation" do
    @tag timeout: @timeout
    test "many processes can schedule heartbeats concurrently" do
      # Simulate many WebSocket processes each scheduling heartbeats
      tasks =
        for i <- 1..@session_count do
          Task.async(fn ->
            user_id = i + 800_000

            # Simulate heartbeat scheduling (like WebSocket handler does)
            ref = Process.send_after(self(), {:heartbeat, user_id}, 100)

            # Wait for heartbeat
            receive do
              {:heartbeat, ^user_id} -> :ok
            after
              500 ->
                Process.cancel_timer(ref)
                :timeout
            end
          end)
        end

      results = Enum.map(tasks, fn task -> Task.await(task, @timeout) end)

      # All heartbeats should be received
      success_count = Enum.count(results, fn r -> r == :ok end)
      timeout_count = Enum.count(results, fn r -> r == :timeout end)

      IO.puts("\nHeartbeat simulation: #{success_count} success, #{timeout_count} timeout")

      # Allow some timeouts due to system load, but most should succeed
      assert success_count > @session_count * 0.9
    end
  end

  # ==============================================================
  # Scalability Report
  # ==============================================================

  describe "scalability report" do
    @tag timeout: 60_000
    test "full scalability benchmark" do
      IO.puts("\n" <> String.duplicate("=", 60))
      IO.puts("Aguardia Server Scalability Report")
      IO.puts(String.duplicate("=", 60))

      # 1. Registry benchmark
      IO.puts("\n1. Registry Operations")

      {time_us, _} =
        :timer.tc(fn ->
          users =
            for i <- 1..1000 do
              user_id = i + 900_000
              keys = generate_user_keys()

              Registry.register(Aguardia.SessionRegistry, user_id, %{
                x: keys.x_public,
                ed: keys.ed_public
              })

              user_id
            end

          for user_id <- users do
            Registry.lookup(Aguardia.SessionRegistry, user_id)
          end

          for user_id <- users do
            Registry.unregister(Aguardia.SessionRegistry, user_id)
          end
        end)

      IO.puts("   1000 register/lookup/unregister cycles: #{div(time_us, 1000)}ms")

      # 2. Command processing benchmark
      IO.puts("\n2. Command Processing")

      {time_us, _} =
        :timer.tc(fn ->
          for i <- 1..1000 do
            json = Jason.encode!(%{action: "status"})
            Commands.handle(i, json)
          end
        end)

      IO.puts("   1000 status commands: #{div(time_us, 1000)}ms")

      # 3. Crypto benchmark
      IO.puts("\n3. Cryptographic Operations")
      keys = generate_user_keys()

      {time_us, _} =
        :timer.tc(fn ->
          for _ <- 1..100 do
            generate_user_keys()
          end
        end)

      IO.puts("   100 keypair generations: #{div(time_us, 1000)}ms")

      {time_us, _} =
        :timer.tc(fn ->
          for _ <- 1..100 do
            Crypto.encrypt_and_sign("test", keys.x_secret, keys.ed_secret, keys.x_public)
          end
        end)

      IO.puts("   100 encrypt+sign: #{div(time_us, 1000)}ms")

      # 4. Server state access benchmark
      IO.puts("\n4. Server State Access")

      {time_us, _} =
        :timer.tc(fn ->
          for _ <- 1..10000 do
            ServerState.public_x()
            ServerState.public_ed()
          end
        end)

      IO.puts("   10000 state accesses: #{div(time_us, 1000)}ms")

      IO.puts("\n" <> String.duplicate("=", 60))
      IO.puts("Report Complete")
      IO.puts(String.duplicate("=", 60))
    end
  end
end

defmodule Aguardia.EmailCodes do
  @moduledoc """
  Stores email verification codes with TTL.

  Uses ETS for fast concurrent access and a periodic cleanup process
  to remove expired codes.
  """
  use GenServer

  require Logger

  @table __MODULE__
  @cleanup_interval :timer.seconds(60)

  # Public API

  @doc """
  Start the EmailCodes GenServer.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Get an existing code or create a new one for the given email.

  Returns `{code, is_new}` where:
  - `code` is a 6-digit string like "123456"
  - `is_new` is `true` if a new code was generated, `false` if existing
  """
  @spec get_or_create(String.t()) :: {String.t(), boolean()}
  def get_or_create(email) do
    GenServer.call(__MODULE__, {:get_or_create, email})
  end

  @doc """
  Check if a code is valid for the given email.
  Does not consume the code.
  """
  @spec valid?(String.t(), String.t()) :: boolean()
  def valid?(email, code) do
    case :ets.lookup(@table, email) do
      [{^email, ^code, expires_at}] ->
        System.monotonic_time(:millisecond) < expires_at

      _ ->
        false
    end
  end

  @doc """
  Verify that a code matches for the given email.
  Returns `true` if valid, `false` otherwise.
  """
  @spec verify(String.t(), String.t()) :: boolean()
  def verify(email, code) do
    valid?(email, code)
  end

  @doc """
  Delete the code for an email (after successful login).
  """
  @spec delete(String.t()) :: :ok
  def delete(email) do
    :ets.delete(@table, email)
    :ok
  end

  # GenServer Callbacks

  @impl true
  def init(_) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:get_or_create, email}, _from, state) do
    now = System.monotonic_time(:millisecond)
    ttl_ms = Application.get_env(:aguardia, :email_code_expired_sec, 600) * 1000
    expires_at = now + ttl_ms

    result =
      case :ets.lookup(@table, email) do
        [{^email, existing_code, existing_expires}] when existing_expires > now ->
          # Code still valid, return existing
          {existing_code, false}

        _ ->
          # No code or expired, generate new
          code = generate_code()
          :ets.insert(@table, {email, code, expires_at})
          {code, true}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private Functions

  defp generate_code do
    :rand.uniform(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired do
    now = System.monotonic_time(:millisecond)

    # Select and delete expired entries
    expired =
      :ets.select(@table, [
        {{:"$1", :_, :"$3"}, [{:<, :"$3", now}], [:"$1"]}
      ])

    Enum.each(expired, &:ets.delete(@table, &1))

    if length(expired) > 0 do
      Logger.debug("Cleaned up #{length(expired)} expired email codes")
    end
  end
end

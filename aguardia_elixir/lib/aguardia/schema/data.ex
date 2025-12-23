defmodule Aguardia.Schema.Data do
  @moduledoc """
  Ecto schema for the data table.

  Stores telemetry data from devices. Each record is associated with a device
  and contains a timestamp and arbitrary JSON payload.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Aguardia.Repo
  alias Aguardia.Schema.User

  schema "data" do
    belongs_to(:device, User, foreign_key: :device_id)
    field(:time_send, :utc_datetime_usec)
    field(:time, :utc_datetime_usec)
    field(:payload, :map)
  end

  @required_fields [:device_id, :time_send, :time, :payload]

  @doc """
  Changeset for creating a new data record.
  """
  def changeset(data, attrs) do
    data
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:device_id)
  end

  @doc """
  Insert a new telemetry data record.
  """
  @spec insert(integer(), map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def insert(device_id, payload) do
    now = DateTime.utc_now()

    # Extract time from payload if present, otherwise use current time
    data_time =
      case payload do
        %{"time" => t} when is_integer(t) -> DateTime.from_unix!(t)
        %{time: t} when is_integer(t) -> DateTime.from_unix!(t)
        _ -> now
      end

    attrs = %{
      device_id: device_id,
      time_send: now,
      time: data_time,
      payload: payload
    }

    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Read data records for a device within a time range.

  - `device_id`: The device to read data for
  - `time_from`: Start of time range (Unix timestamp, inclusive)
  - `time_to`: End of time range (Unix timestamp, inclusive)
  - `limit`: Maximum number of records to return (default 10000)

  Returns a list of maps with :id, :time, and :payload fields.
  """
  @spec read(integer(), integer(), integer(), integer()) :: [map()]
  def read(device_id, time_from, time_to, limit \\ 10_000) do
    from_dt = DateTime.from_unix!(time_from)
    to_dt = DateTime.from_unix!(time_to)

    __MODULE__
    |> where([d], d.device_id == ^device_id)
    |> where([d], d.time >= ^from_dt and d.time <= ^to_dt)
    |> order_by([d], asc: d.time)
    |> limit(^limit)
    |> select([d], %{
      id: d.id,
      time: d.time,
      payload: d.payload
    })
    |> Repo.all()
    |> Enum.map(fn record ->
      %{
        id: record.id,
        time: DateTime.to_unix(record.time),
        payload: record.payload
      }
    end)
  end

  @doc """
  Delete a specific data record.

  Verifies that the record belongs to the specified device.
  """
  @spec delete(integer(), integer()) :: :ok | {:error, :not_found}
  def delete(data_id, device_id) do
    query =
      __MODULE__
      |> where([d], d.id == ^data_id and d.device_id == ^device_id)

    case Repo.delete_all(query) do
      {0, _} -> {:error, :not_found}
      {_, _} -> :ok
    end
  end

  @doc """
  Delete all data for a device.
  """
  @spec delete_all_for_device(integer()) :: :ok
  def delete_all_for_device(device_id) do
    __MODULE__
    |> where([d], d.device_id == ^device_id)
    |> Repo.delete_all()

    :ok
  end
end

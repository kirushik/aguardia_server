defmodule Aguardia.Schema.User do
  @moduledoc """
  Ecto schema for the users table.

  Users can be either human users (with email) or devices (without email).
  Each user/device has unique X25519 and Ed25519 public keys.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Aguardia.Repo

  schema "users" do
    field(:public_x, :binary)
    field(:public_ed, :binary)
    field(:email, :string)
    field(:admin_info, :map)
    field(:info, :map)
    field(:time_reg, :utc_datetime_usec)
    field(:time_upd, :utc_datetime_usec)
  end

  @required_fields [:public_x, :public_ed]
  @optional_fields [:email, :admin_info, :info]

  @doc """
  Changeset for creating a new user/device.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_binary_size(:public_x, 32)
    |> validate_binary_size(:public_ed, 32)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "invalid email format")
    |> unique_constraint(:public_x)
    |> unique_constraint(:public_ed)
    |> unique_constraint(:email)
  end

  # Custom validator for binary byte size (validate_length doesn't work for binaries)
  defp validate_binary_size(changeset, field, size) do
    validate_change(changeset, field, fn _field, value ->
      if is_binary(value) and byte_size(value) == size do
        []
      else
        [{field, "must be #{size} bytes"}]
      end
    end)
  end

  @doc """
  Changeset for updating user info.
  """
  def update_info_changeset(user, attrs) do
    user
    |> cast(attrs, [:info])
  end

  @doc """
  Find a user by their Ed25519 public key.
  """
  @spec get_by_public_ed(binary()) :: %__MODULE__{} | nil
  def get_by_public_ed(public_ed) when byte_size(public_ed) == 32 do
    Repo.get_by(__MODULE__, public_ed: public_ed)
  end

  @doc """
  Find a user by their X25519 and Ed25519 public keys.
  """
  @spec get_by_keys(binary(), binary()) :: %__MODULE__{} | nil
  def get_by_keys(public_x, public_ed)
      when byte_size(public_x) == 32 and byte_size(public_ed) == 32 do
    __MODULE__
    |> where([u], u.public_x == ^public_x and u.public_ed == ^public_ed)
    |> Repo.one()
  end

  @doc """
  Get user ID by their keys.
  Returns {:ok, id} or {:error, :not_found}.
  """
  @spec get_id_by_keys(binary(), binary()) :: {:ok, integer()} | {:error, :not_found}
  def get_id_by_keys(public_x, public_ed) do
    case get_by_keys(public_x, public_ed) do
      %__MODULE__{id: id} -> {:ok, id}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Upsert a user by email (for login flow).
  Creates new user or updates existing user's keys.
  """
  @spec upsert_by_email(String.t(), binary(), binary()) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def upsert_by_email(email, public_x, public_ed) do
    attrs = %{
      email: email,
      public_x: public_x,
      public_ed: public_ed
    }

    Repo.insert(
      changeset(%__MODULE__{}, attrs),
      on_conflict: [set: [public_x: public_x, public_ed: public_ed]],
      conflict_target: :email,
      returning: true
    )
  end

  @doc """
  Create a new device (no email).
  """
  @spec create_device(binary(), binary(), map(), map()) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t() | :already_exists}
  def create_device(public_x, public_ed, info \\ %{}, admin_info \\ %{}) do
    attrs = %{
      public_x: public_x,
      public_ed: public_ed,
      info: info,
      admin_info: admin_info
    }

    case Repo.insert(changeset(%__MODULE__{}, attrs), on_conflict: :nothing, returning: true) do
      {:ok, %__MODULE__{id: nil}} -> {:error, :already_exists}
      {:ok, user} -> {:ok, user}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Delete a user by ID.
  """
  @spec delete(integer()) :: :ok | {:error, :not_found}
  def delete(id) do
    case Repo.get(__MODULE__, id) do
      nil ->
        {:error, :not_found}

      user ->
        Repo.delete(user)
        :ok
    end
  end

  @doc """
  Check if the given keys match the user with the given ID.
  Used for authorization (remote control).
  """
  @spec owns?(integer(), binary(), binary()) :: boolean()
  def owns?(user_id, public_x, public_ed) do
    __MODULE__
    |> where([u], u.id == ^user_id and u.public_x == ^public_x and u.public_ed == ^public_ed)
    |> Repo.exists?()
  end

  @doc """
  Get user info by ID.
  """
  @spec get_info(integer()) :: {:ok, map()} | {:error, :not_found}
  def get_info(user_id) do
    case Repo.get(__MODULE__, user_id) do
      nil ->
        {:error, :not_found}

      user ->
        {:ok,
         %{
           info: user.info,
           time_reg: user.time_reg && DateTime.to_unix(user.time_reg),
           time_upd: user.time_upd && DateTime.to_unix(user.time_upd)
         }}
    end
  end

  @doc """
  Update user info.
  """
  @spec update_info(integer(), map()) :: :ok | {:error, :not_found | Ecto.Changeset.t()}
  def update_info(user_id, info) do
    case Repo.get(__MODULE__, user_id) do
      nil ->
        {:error, :not_found}

      user ->
        case user |> update_info_changeset(%{info: info}) |> Repo.update() do
          {:ok, _} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end
end

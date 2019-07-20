defmodule Boilerplate.User do
  @moduledoc """
  A user of the system. How exotic!
  """

  use Ecto.Schema
  require Ecto.Query
  import Ecto.Changeset
  alias Boilerplate.{Repo, Membership}
  alias Ecto.Query

  @required_params [:email, :name]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field(:email, :string)
    field(:email_confirmed_at, :utc_datetime)
    field(:name, :string)
    field(:password_hash, :string)
    field(:password, :string, virtual: true)
    has_many(:memberships, Membership)
    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  defp validate(changeset) do
    changeset
    |> validate_required(@required_params)
    |> validate_format(:email, ~r/.@.+\../)
    |> validate_length(:password, min: 8, max: 100)
    |> validate_length(:password, min: 1, max: 100)
    |> unique_constraint(:email)
    |> put_password_hash()
  end

  def changeset(user, params) do
    user
    |> cast(params, @required_params)
    |> cast(params, [:password, :email_confirmed_at])
    |> validate()
  end

  @doc """
  Extract and validate changes to a user relevent to registration.
  """
  def registration_changeset(user, params \\ %{}) do
    user
    |> cast(params, [:password | @required_params])
    |> validate_required([:password])
    |> validate()
  end

  @doc """
  Allows a user to self-register.
  """
  def register(params) do
    %__MODULE__{}
    |> registration_changeset(params)
    |> Repo.insert()
  end

  @doc """
  Look up the user with the given id in the database.
  """
  @spec fetch(String.t()) :: {:ok, t} | :not_found
  def fetch(id) do
    __MODULE__
    |> Query.where(id: ^id)
    |> Query.preload(memberships: [:organisation])
    |> Repo.fetch()
  end

  @doc """
  Look up the user with the given email in the database.
  """
  @spec fetch_by_email(String.t()) :: {:ok, t} | :not_found
  def fetch_by_email(email) do
    __MODULE__
    |> Query.where(email: ^email)
    |> Repo.fetch()
  end

  @doc """
  Insert a new user into the database.
  """
  @spec insert(map | keyword) :: {:ok, t} | {:error, Ecto.Changeset.t()}
  def insert(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  @doc """
  Insert a new User into the database, fetching it there already is one
  with the given email.
  """
  @spec fetch_or_insert(map | keyword) :: {:ok, t} | {:error, Ecto.Changeset.t()}
  def fetch_or_insert(params) do
    with :not_found <- fetch_by_email(params[:email]) do
      insert(params)
    end
  end

  defp put_password_hash(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: pass}} when pass != nil ->
        put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(pass))

      _ ->
        changeset
    end
  end

  @doc """
  Attempt to find a user for a given email/password combination.
  """
  def fetch_for_credentials(nil, _), do: :email_required
  def fetch_for_credentials("", _), do: :email_required

  def fetch_for_credentials(email, password) do
    with {:ok, user} <- fetch_by_email(email),
         true <- Bcrypt.verify_pass(password, user.password_hash) do
      {:ok, user}
    else
      :not_found ->
        :not_found

      false ->
        :incorrect_password
    end
  end

  @doc """
  Set the `email_confirmed_at` field to the current time.
  """
  @spec confirm_email(t()) :: {:ok, t()}
  def confirm_email(user) do
    {:ok, _} =
      user
      |> Ecto.Changeset.change(%{email_confirmed_at: DateTime.utc_now()})
      |> Repo.update()

    :ok
  end

  @spec update_password(t(), String.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update_password(user, new_password) do
    user
    |> Ecto.Changeset.change(password: new_password)
    |> put_password_hash
    |> validate()
    |> Repo.update()
  end
end

defmodule TesIdle.Schemas.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :username, :string
    field :email, :string
    field :password_hash, :string
    field :is_admin, :boolean, default: false
    field :is_online, :boolean, default: false
    field :last_seen, :utc_datetime

    has_many :heroes, TesIdle.Schemas.Hero

    timestamps(inserted_at: :created_at, type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password_hash, :is_admin, :is_online, :last_seen])
    |> validate_required([:username, :email, :password_hash])
    |> unique_constraint(:username)
    |> unique_constraint(:email)
  end
end

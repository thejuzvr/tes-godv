defmodule TesIdle.Schemas.GuildMember do
  @moduledoc "G-0: членство (одна гильдия на игрока — user_id unique). Очки/вклад копятся в G-1."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ["leader", "officer", "member"]

  schema "guild_members" do
    field :role, :string, default: "member"
    field :points, :integer, default: 0
    field :contributed, :integer, default: 0
    belongs_to :guild, TesIdle.Schemas.Guild
    belongs_to :user, TesIdle.Schemas.User

    timestamps(inserted_at: :joined_at, updated_at: false)
  end

  def roles, do: @roles

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:guild_id, :user_id, :role, :points, :contributed, :joined_at])
    |> validate_required([:guild_id, :user_id])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:user_id)
  end
end

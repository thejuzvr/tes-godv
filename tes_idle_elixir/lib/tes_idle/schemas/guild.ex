defmodule TesIdle.Schemas.Guild do
  @moduledoc """
  G-0: гильдия. Одна на игрока (guild_members.user_id unique), лидер = user.
  Экономика/уровни/бафы — G-1, конфиг `game_configs["guild"]`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @emblems ["🛡️", "🐺", "🐉", "🌙", "⚔️", "🔥", "🕯️", "🦅"]
  @policies ["open", "request", "invite"]

  def emblems, do: @emblems

  schema "guilds" do
    field :name, :string
    field :motto, :string
    field :emblem, :string
    field :description, :string
    field :level, :integer, default: 1
    field :exp, :integer, default: 0
    field :policy, :string, default: "open"
    field :treasury, :integer, default: 0
    field :boost_until, :naive_datetime

    belongs_to :leader, TesIdle.Schemas.User, foreign_key: :leader_id

    has_many :members, TesIdle.Schemas.GuildMember
    has_many :offerings, TesIdle.Schemas.GuildOffering
    has_many :messages, TesIdle.Schemas.GuildMessage

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(guild, attrs) do
    guild
    |> cast(attrs, [:name, :motto, :emblem, :description, :leader_id, :level, :exp, :policy])
    |> validate_required([:name, :leader_id])
    |> update_change(:name, &String.trim/1)
    |> validate_length(:name, min: 3, max: 24)
    |> validate_format(:name, ~r/^[\p{L}\p{N} \-']+$/u, message: "только буквы, цифры, пробел, дефис")
    |> validate_inclusion(:emblem, @emblems)
    |> validate_length(:motto, max: 80)
    |> validate_inclusion(:policy, @policies)
    |> unique_constraint(:name, name: :guilds_name_unique_idx)
  end
end

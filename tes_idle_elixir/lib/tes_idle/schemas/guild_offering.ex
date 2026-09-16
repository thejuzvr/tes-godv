defmodule TesIdle.Schemas.GuildOffering do
  @moduledoc "G-1: журнал подношений (аудит + аналитика). Таблица создана в G-0."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "guild_offerings" do
    field :kind, :string, default: "gold"
    field :ref_id, :binary_id
    field :amount, :integer, default: 0
    field :points, :integer, default: 0

    belongs_to :guild, TesIdle.Schemas.Guild
    belongs_to :user, TesIdle.Schemas.User
    belongs_to :hero, TesIdle.Schemas.Hero

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end
end

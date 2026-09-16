defmodule TesIdle.Schemas.GuildNews do
  @moduledoc """
  G-5: вести гильдий — мировой фид (основание, уровни, достижения).
  Читать: GET /guilds/news (Wiki «Вести гильдий»); гильдия может распуститься — guild_id nullable.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "guild_news" do
    field :template_type, :string
    field :text, :string

    belongs_to :guild, TesIdle.Schemas.Guild

    timestamps(inserted_at: :created_at, updated_at: false)
  end
end

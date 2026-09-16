defmodule TesIdle.Schemas.GuildMessage do
  @moduledoc "G-2: чат гильдии (user_id null = системное). Таблица создана в G-0."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "guild_messages" do
    field :body, :string
    field :kind, :string, default: "chat"

    belongs_to :guild, TesIdle.Schemas.Guild
    belongs_to :user, TesIdle.Schemas.User

    timestamps(inserted_at: :inserted_at, updated_at: false)
  end
end

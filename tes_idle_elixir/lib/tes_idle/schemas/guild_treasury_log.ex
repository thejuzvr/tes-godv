defmodule TesIdle.Schemas.GuildTreasuryLog do
  @moduledoc """
  G-6: журнал казны гильдии (deposit — вклад члена, withdraw — трата на проект).
  Золото в казне не возвращается героям — только тратится на гильдейские проекты.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "guild_treasury_log" do
    field :kind, :string
    field :amount, :integer
    field :balance_after, :integer

    belongs_to :guild, TesIdle.Schemas.Guild
    belongs_to :user, TesIdle.Schemas.User

    timestamps(inserted_at: :created_at, updated_at: false)
  end
end

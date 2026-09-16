defmodule TesIdle.Schemas.GuildApplication do
  @moduledoc """
  G-4: заявка на вступление в гильдию (policy="request").
  Статусы: pending | approved | rejected. Одна pending на юзера (частичный unique).
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ["pending", "approved", "rejected"]
  def statuses, do: @statuses

  schema "guild_applications" do
    field :status, :string, default: "pending"

    belongs_to :guild, TesIdle.Schemas.Guild
    belongs_to :user, TesIdle.Schemas.User

    timestamps(inserted_at: :created_at, updated_at: false)
  end
end

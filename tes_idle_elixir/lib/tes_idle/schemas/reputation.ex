defmodule TesIdle.Schemas.Reputation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "reputations" do
    field :faction, :string
    field :value, :integer, default: 0
    field :level, :string, default: "Нейтралитет"

    belongs_to :hero, TesIdle.Schemas.Hero, type: :binary_id

    # timestamps()
  end

  def changeset(reputation, attrs) do
    reputation
    |> cast(attrs, [:faction, :value, :level, :hero_id])
    |> validate_required([:faction, :hero_id])
  end
end

defmodule TesIdle.Schemas.Equipment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "equipment" do
    belongs_to :hero, TesIdle.Schemas.Hero, type: :binary_id
    belongs_to :weapon, TesIdle.Schemas.Item, type: :binary_id
    belongs_to :head, TesIdle.Schemas.Item, type: :binary_id
    belongs_to :body, TesIdle.Schemas.Item, type: :binary_id
    belongs_to :legs, TesIdle.Schemas.Item, type: :binary_id
    belongs_to :ring, TesIdle.Schemas.Item, type: :binary_id
    belongs_to :amulet, TesIdle.Schemas.Item, type: :binary_id

    # timestamps()
  end

  def changeset(equipment, attrs) do
    equipment
    |> cast(attrs, [:hero_id, :weapon_id, :head_id, :body_id, :legs_id, :ring_id, :amulet_id])
    |> validate_required([:hero_id])
    |> unique_constraint(:hero_id)
  end
end

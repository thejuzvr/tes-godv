defmodule TesIdle.Schemas.HeroRelationshipSide do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "hero_relationship_sides" do
    field :affinity, :integer, default: 0
    field :tags, {:array, :string}, default: []
    field :private_payload, :map, default: %{}

    belongs_to :relationship, TesIdle.Schemas.HeroRelationship
    belongs_to :hero, TesIdle.Schemas.Hero

    timestamps(inserted_at: :created_at)
  end

  def changeset(side, attrs) do
    side
    |> cast(attrs, [:relationship_id, :hero_id, :affinity, :tags, :private_payload])
    |> validate_required([:relationship_id, :hero_id, :affinity])
    |> unique_constraint([:relationship_id, :hero_id],
      name: :hero_relationship_sides_relationship_hero_uidx
    )
    |> foreign_key_constraint(:relationship_id)
    |> foreign_key_constraint(:hero_id)
  end
end

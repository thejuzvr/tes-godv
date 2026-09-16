defmodule TesIdle.Schemas.HeroRelationship do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "hero_relationships" do
    field :familiarity, :integer, default: 0
    field :encounter_count, :integer, default: 0
    field :cooldown_until, :naive_datetime
    field :shared_tags, {:array, :string}, default: []

    belongs_to :hero_low, TesIdle.Schemas.Hero
    belongs_to :hero_high, TesIdle.Schemas.Hero
    has_many :sides, TesIdle.Schemas.HeroRelationshipSide, foreign_key: :relationship_id

    timestamps(inserted_at: :created_at)
  end

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [
      :hero_low_id,
      :hero_high_id,
      :familiarity,
      :encounter_count,
      :cooldown_until,
      :shared_tags
    ])
    |> validate_required([:hero_low_id, :hero_high_id, :familiarity, :encounter_count])
    |> validate_number(:familiarity, greater_than_or_equal_to: 0)
    |> validate_number(:encounter_count, greater_than_or_equal_to: 0)
    |> validate_ordered_pair()
    |> unique_constraint([:hero_low_id, :hero_high_id], name: :hero_relationships_pair_uidx)
    |> foreign_key_constraint(:hero_low_id)
    |> foreign_key_constraint(:hero_high_id)
  end

  defp validate_ordered_pair(changeset) do
    low_id = get_field(changeset, :hero_low_id)
    high_id = get_field(changeset, :hero_high_id)

    if is_binary(low_id) and is_binary(high_id) and low_id >= high_id do
      add_error(changeset, :hero_high_id, "must be greater than hero_low_id")
    else
      changeset
    end
  end
end

defmodule TesIdle.Schemas.EncounterClaim do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "encounter_claims" do
    field :round, :integer
    field :claimed_at, :naive_datetime, autogenerate: {NaiveDateTime, :utc_now, []}

    belongs_to :hero, TesIdle.Schemas.Hero
    belongs_to :encounter, TesIdle.Schemas.HeroEncounter
  end

  def changeset(claim, attrs) do
    claim
    |> cast(attrs, [:round, :hero_id, :encounter_id, :claimed_at])
    |> validate_required([:round, :hero_id])
    |> unique_constraint([:round, :hero_id], name: :encounter_claims_round_hero_uidx)
    |> foreign_key_constraint(:hero_id)
    |> foreign_key_constraint(:encounter_id)
  end
end

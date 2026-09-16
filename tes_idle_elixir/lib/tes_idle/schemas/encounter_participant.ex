defmodule TesIdle.Schemas.EncounterParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "encounter_participants" do
    field :role, :string
    field :private_payload, :map, default: %{}

    belongs_to :encounter, TesIdle.Schemas.HeroEncounter
    belongs_to :hero, TesIdle.Schemas.Hero

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:encounter_id, :hero_id, :role, :private_payload])
    |> validate_required([:encounter_id, :hero_id])
    |> unique_constraint([:encounter_id, :hero_id],
      name: :encounter_participants_encounter_hero_uidx
    )
    |> foreign_key_constraint(:encounter_id)
    |> foreign_key_constraint(:hero_id)
  end
end

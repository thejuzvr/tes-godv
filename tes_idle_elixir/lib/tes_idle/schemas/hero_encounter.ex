defmodule TesIdle.Schemas.HeroEncounter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "hero_encounters" do
    field :round, :integer
    field :kind, :string
    field :status, :string, default: "pending"
    field :shared_payload, :map, default: %{}
    field :idempotency_key, :string

    belongs_to :hero_low, TesIdle.Schemas.Hero
    belongs_to :hero_high, TesIdle.Schemas.Hero
    belongs_to :location, TesIdle.Schemas.Location

    has_many :claims, TesIdle.Schemas.EncounterClaim, foreign_key: :encounter_id
    has_many :participants, TesIdle.Schemas.EncounterParticipant, foreign_key: :encounter_id
    has_many :journal_entries, TesIdle.Schemas.JournalEntry, foreign_key: :encounter_id
    has_many :outbox_events, TesIdle.Schemas.EventOutbox, foreign_key: :encounter_id

    timestamps(inserted_at: :created_at)
  end

  def changeset(encounter, attrs) do
    encounter
    |> cast(attrs, [
      :hero_low_id,
      :hero_high_id,
      :round,
      :location_id,
      :kind,
      :status,
      :shared_payload,
      :idempotency_key
    ])
    |> validate_required([
      :hero_low_id,
      :hero_high_id,
      :round,
      :location_id,
      :kind,
      :status,
      :idempotency_key
    ])
    |> validate_ordered_pair()
    |> unique_constraint(:idempotency_key, name: :hero_encounters_idempotency_uidx)
    |> foreign_key_constraint(:hero_low_id)
    |> foreign_key_constraint(:hero_high_id)
    |> foreign_key_constraint(:location_id)
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

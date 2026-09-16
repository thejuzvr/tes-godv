defmodule TesIdle.Schemas.EventOutbox do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "event_outbox" do
    field :event_type, :string
    field :payload, :map, default: %{}
    field :idempotency_key, :string
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :available_at, :naive_datetime, autogenerate: {NaiveDateTime, :utc_now, []}
    field :processed_at, :naive_datetime
    field :last_error, :string

    belongs_to :encounter, TesIdle.Schemas.HeroEncounter

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :encounter_id,
      :event_type,
      :payload,
      :idempotency_key,
      :status,
      :attempts,
      :available_at,
      :processed_at,
      :last_error
    ])
    |> validate_required([
      :event_type,
      :payload,
      :idempotency_key,
      :status,
      :attempts,
      :available_at
    ])
    |> validate_number(:attempts, greater_than_or_equal_to: 0)
    |> unique_constraint(:idempotency_key, name: :event_outbox_idempotency_uidx)
    |> foreign_key_constraint(:encounter_id)
  end
end

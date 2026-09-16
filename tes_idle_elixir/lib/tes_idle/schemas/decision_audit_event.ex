defmodule TesIdle.Schemas.DecisionAuditEvent do
  @moduledoc "Long-lived, append-only Brain decision and action telemetry."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "decision_audit_events" do
    field :game_day, :integer
    field :game_hour, :float
    field :event_type, :string
    field :goal, :string
    field :action, :string
    field :utility, :float
    # JSONB object; audit reasons are stored under the stable `items` key.
    field :reasons, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :hero, TesIdle.Schemas.Hero

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :hero_id,
      :game_day,
      :game_hour,
      :event_type,
      :goal,
      :action,
      :utility,
      :reasons,
      :metadata
    ])
    |> validate_required([:hero_id, :event_type])
    |> validate_inclusion(:event_type, [
      "intent_selected",
      "intent_held",
      "intent_switched",
      "action_started",
      "action_completed",
      "action_failed"
    ])
    |> foreign_key_constraint(:hero_id)
  end
end

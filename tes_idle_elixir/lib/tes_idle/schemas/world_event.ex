defmodule TesIdle.Schemas.WorldEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "world_events" do
    field :event_type, :string
    field :title, :string
    field :payload, :map, default: %{}
    field :active, :boolean, default: true
    field :started_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :created_at, :utc_datetime
  end

  def changeset(world_event, attrs) do
    world_event
    |> cast(attrs, [:event_type, :title, :payload, :active, :started_at, :expires_at])
    |> validate_required([:event_type])
  end
end

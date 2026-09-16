defmodule TesIdle.Schemas.WorldState do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "world_state" do
    field :key, :string, primary_key: true
    field :value, :map, default: %{}
    field :updated_at, :utc_datetime
  end

  def changeset(world_state, attrs) do
    world_state
    |> cast(attrs, [:key, :value, :updated_at])
    |> validate_required([:key])
  end
end

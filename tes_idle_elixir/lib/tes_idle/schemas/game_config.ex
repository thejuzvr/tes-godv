defmodule TesIdle.Schemas.GameConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "game_configs" do
    field :key, :string
    field :value, :string
    field :description, :string, default: ""

    timestamps(inserted_at: false, updated_at: :updated_at)
  end

  def changeset(game_config, attrs) do
    game_config
    |> cast(attrs, [:key, :value, :description])
    |> validate_required([:key, :value])
    |> unique_constraint(:key)
  end
end

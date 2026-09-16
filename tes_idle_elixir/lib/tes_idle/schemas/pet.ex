defmodule TesIdle.Schemas.Pet do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "pets" do
    field :species, :string
    field :name, :string
    field :mood, :float, default: 60.0
    field :hunger, :float, default: 30.0
    field :loyalty, :float, default: 70.0
    # active | cooldown (гибель, ждёт revive_at) | gone (убежал при лояльности 0)
    field :status, :string, default: "active"
    field :revive_at, :utc_datetime
    field :created_at, :utc_datetime

    belongs_to :hero, TesIdle.Schemas.Hero, type: :binary_id
  end

  def changeset(pet, attrs) do
    pet
    |> cast(attrs, [:species, :name, :mood, :hunger, :loyalty, :status, :revive_at, :hero_id])
    |> validate_required([:species, :name, :hero_id])
    |> validate_inclusion(:species, [
      # обычные
      "wolf", "owl", "cat", "lizard", "goat", "fox", "raven",
      # комичные
      "goose", "hedgehog", "moth", "rock", "turnip", "butter", "skeleton", "cheese",
    ])
    |> validate_inclusion(:status, ["active", "cooldown", "gone"])
  end
end

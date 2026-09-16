defmodule TesIdle.Schemas.InventoryItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "inventory_items" do
    field :quantity, :integer, default: 1

    belongs_to :hero, TesIdle.Schemas.Hero, type: :binary_id
    belongs_to :item, TesIdle.Schemas.Item, type: :binary_id

    # timestamps()
  end

  def changeset(inventory_item, attrs) do
    inventory_item
    |> cast(attrs, [:quantity, :hero_id, :item_id])
    |> validate_required([:hero_id, :item_id])
  end
end

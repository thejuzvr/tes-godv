defmodule TesIdle.Schemas.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "items" do
    field :name, :string
    field :description, :string, default: ""
    field :item_type, :string  # consumable, equipment, junk
    field :rarity, :string, default: "common"
    field :icon, :string, default: "?"
    field :weight, :float, default: 1.0
    field :sell_price, :integer, default: 1
    field :is_active, :boolean, default: true
    # Семантические теги: ["fish", "herb", "component", "lockpick", "stolen", ...]
    field :tags, {:array, :string}, default: []

    # Consumable effects
    field :heal_hp, :integer, default: 0
    field :heal_mp, :integer, default: 0
    field :heal_sp, :integer, default: 0
    field :reduce_hunger, :float, default: 0.0
    field :reduce_fatigue, :float, default: 0.0
    field :boost_morale, :float, default: 0.0
    field :buff_attack, :integer, default: 0
    field :buff_duration_ticks, :integer, default: 0
    field :soul_restore, :float, default: 0.0

    # Equipment stats
    field :equip_slot, :string
    field :attack_bonus, :integer, default: 0
    field :defense_bonus, :integer, default: 0
    field :hp_bonus, :integer, default: 0
    field :speed_bonus, :float, default: 0.0

    # timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :name, :description, :item_type, :rarity, :icon, :weight, :sell_price, :is_active,
      :tags,
      :heal_hp, :heal_mp, :heal_sp, :reduce_hunger, :reduce_fatigue, :boost_morale,
      :buff_attack, :buff_duration_ticks, :soul_restore,
      :equip_slot, :attack_bonus, :defense_bonus, :hp_bonus, :speed_bonus,
    ])
    |> validate_required([:name, :item_type])
  end
end

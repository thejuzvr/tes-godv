defmodule TesIdle.Schemas.Monster do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "monsters" do
    field :name, :string
    field :description, :string, default: ""
    field :min_level, :integer, default: 1
    field :max_level, :integer, default: 5
    field :hp, :integer, default: 50
    field :attack_min, :integer, default: 5
    field :attack_max, :integer, default: 10
    field :defense, :integer, default: 0
    field :xp_reward, :integer, default: 20
    field :gold_min, :integer, default: 5
    field :gold_max, :integer, default: 15
    field :is_active, :boolean, default: true

    belongs_to :location, TesIdle.Schemas.Location, type: :binary_id
    has_many :loot_table, TesIdle.Schemas.MonsterLoot

    # timestamps()
  end

  def changeset(monster, attrs) do
    monster
    |> cast(attrs, [
      :name, :description, :min_level, :max_level, :hp,
      :attack_min, :attack_max, :defense, :xp_reward,
      :gold_min, :gold_max, :is_active, :location_id,
    ])
    |> validate_required([:name, :hp])
  end
end

defmodule TesIdle.Schemas.MonsterLoot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "monster_loot" do
    field :drop_chance, :float, default: 0.3

    belongs_to :monster, TesIdle.Schemas.Monster, type: :binary_id
    belongs_to :item, TesIdle.Schemas.Item, type: :binary_id

    # timestamps()
  end

  def changeset(monster_loot, attrs) do
    monster_loot
    |> cast(attrs, [:drop_chance, :monster_id, :item_id])
    |> validate_required([:monster_id, :item_id])
  end
end

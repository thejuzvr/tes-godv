defmodule TesIdle.Schemas.Hero do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "heroes" do
    field :name, :string
    field :race, :string
    field :hero_class, :string
    field :level, :integer, default: 1
    field :hp, :integer, default: 100
    field :max_hp, :integer, default: 100
    field :mp, :integer, default: 50
    field :max_mp, :integer, default: 50
    field :sp, :integer, default: 100
    field :max_sp, :integer, default: 100
    field :attack, :integer, default: 10
    field :defense, :integer, default: 5
    field :xp, :integer, default: 0
    field :xp_to_next, :integer, default: 100
    field :gold, :integer, default: 0
    field :state, :string, default: "exploring"
    field :mood, :float, default: 50.0
    field :hunger, :float, default: 30.0
    field :fatigue, :float, default: 30.0
    field :morale, :float, default: 60.0
    field :soul_energy, :float, default: 0.0
    field :max_soul_energy, :float, default: 100.0
    field :game_hour, :float, default: 8.0
    field :game_day, :integer, default: 1
    field :game_era, :string, default: "Эпоха Третьего Престола"
    field :state_data, :string
    field :mood_history, :string
    field :total_play_time_seconds, :integer, default: 0
    field :total_gold_earned, :integer, default: 0
    field :total_kills, :integer, default: 0
    field :is_online, :boolean, default: false
    field :last_activity, :utc_datetime
    field :max_weight, :float, default: 160.0
    field :personality, :map
    # Паспорт мозга (ROADMAP: Часть I) — SHA256(user_id:hero:ordinal), постоянен
    field :brain_hash, :string
    # Навыки активностей: %{"fishing" => 1, "stealth" => 3, ...}
    field :skills, :map, default: %{}

    belongs_to :user, TesIdle.Schemas.User, type: :binary_id
    belongs_to :location, TesIdle.Schemas.Location, type: :binary_id
    has_one :equipment, TesIdle.Schemas.Equipment
    has_many :inventory_items, TesIdle.Schemas.InventoryItem
    has_many :journal_entries, TesIdle.Schemas.JournalEntry
    has_many :reputations, TesIdle.Schemas.Reputation
    has_one :active_quest, TesIdle.Schemas.ActiveQuest

  end

  def changeset(hero, attrs) do
    hero
    |> cast(attrs, [
      :name, :race, :hero_class, :level, :hp, :max_hp, :mp, :max_mp,
      :sp, :max_sp, :attack, :defense, :xp, :xp_to_next, :gold,
      :state, :mood, :hunger, :fatigue, :morale, :soul_energy, :max_soul_energy,
      :game_hour, :game_day, :game_era, :state_data, :mood_history,
      :total_play_time_seconds, :total_gold_earned, :total_kills,
      :is_online, :last_activity, :max_weight, :personality,
      :brain_hash, :skills,
      :user_id, :location_id,
    ])
    |> validate_required([:name, :race, :hero_class])
    # Моджибейка-грабля: имя из cp1251-источника доходит до Postgres как
    # «???????» — каждую непечатаемую букву замещает '?'. Такие имена
    # расползаются по всей хронике ({hero_name} подставит «???????»).
    # Легитимные имена '?' не содержат — запрещаем его целиком.
    |> validate_format(:name, ~r/^[^?]+$/, message: "не может содержать '?' (потерянная кодировка)")
  end
end

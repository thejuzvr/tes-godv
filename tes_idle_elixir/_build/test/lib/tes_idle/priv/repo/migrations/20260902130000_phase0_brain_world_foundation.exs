defmodule TesIdle.Repo.Migrations.Phase0BrainWorldFoundation do
  @moduledoc """
  Фаза 0 (ROADMAP_BRAIN_WORLD.md): фундамент Мозга и Ядра мира.

  - heroes: brain_hash (паспорт мозга), skills (навыки активностей)
  - locations: flags (water/gather_nodes/locked_buildings/guard_level)
  - items: tags (fish/herb/component/lockpick/stolen)
  - pets: питомцы (species, mood/hunger/loyalty, status, revive_at)
  - world_state: снапшот ядра мира (key/value)
  - world_events: история мировых событий
  """

  use Ecto.Migration

  def change do
    alter table(:heroes) do
      add :brain_hash, :string
      add :skills, :map, default: %{}
    end

    alter table(:locations) do
      add :flags, :map, default: %{}
    end

    alter table(:items) do
      add :tags, {:array, :string}, default: []
    end

    create index(:items, [:tags], using: "gin")

    create table(:pets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :hero_id, references(:heroes, type: :binary_id, on_delete: :delete_all), null: false
      add :species, :string, null: false
      add :name, :string, null: false
      add :mood, :float, default: 60.0
      add :hunger, :float, default: 30.0
      add :loyalty, :float, default: 70.0
      add :status, :string, default: "active"
      add :revive_at, :utc_datetime
      add :created_at, :utc_datetime
    end

    create index(:pets, [:hero_id])

    create table(:world_state, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :map, default: %{}
      add :updated_at, :utc_datetime
    end

    create table(:world_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :title, :string
      add :payload, :map, default: %{}
      add :active, :boolean, default: true
      add :started_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :created_at, :utc_datetime
    end

    create index(:world_events, [:active])
  end
end

defmodule TesIdle.Schemas.Quest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "quests" do
    field :name, :string
    field :description, :string, default: ""
    field :difficulty, :string, default: "Лёгкий"
    field :xp_reward, :integer, default: 100
    field :gold_reward, :integer, default: 50
    field :steps_total, :integer, default: 1
    field :is_active, :boolean, default: true

    belongs_to :location, TesIdle.Schemas.Location, type: :binary_id
    has_many :steps, TesIdle.Schemas.QuestStep

    # timestamps()
  end

  def changeset(quest, attrs) do
    quest
    |> cast(attrs, [:name, :description, :difficulty, :xp_reward, :gold_reward, :steps_total, :is_active, :location_id])
    |> validate_required([:name])
  end
end

defmodule TesIdle.Schemas.QuestStep do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "quest_steps" do
    field :step_order, :integer
    field :description, :string
    field :step_type, :string, default: "explore"
    field :target_count, :integer, default: 1

    belongs_to :quest, TesIdle.Schemas.Quest, type: :binary_id

    # timestamps()
  end

  def changeset(quest_step, attrs) do
    quest_step
    |> cast(attrs, [:step_order, :description, :step_type, :target_count, :quest_id])
    |> validate_required([:step_order, :description, :quest_id])
  end
end

defmodule TesIdle.Schemas.ActiveQuest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "active_quests" do
    field :current_step, :integer, default: 1
    field :current_progress, :integer, default: 0

    belongs_to :hero, TesIdle.Schemas.Hero, type: :binary_id
    belongs_to :quest, TesIdle.Schemas.Quest, type: :binary_id

    timestamps(inserted_at: :started_at, updated_at: false)
  end

  def changeset(active_quest, attrs) do
    active_quest
    |> cast(attrs, [:current_step, :current_progress, :hero_id, :quest_id])
    |> validate_required([:hero_id, :quest_id])
  end
end

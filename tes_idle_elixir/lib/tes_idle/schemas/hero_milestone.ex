defmodule TesIdle.Schemas.HeroMilestone do
  @moduledoc """
  Памятная веха героя — то, что переживает очистку хроники.

  Храним **снимок отображаемого текста**, а не ссылку на шаблон: шаблон могут
  изменить или удалить, и тогда памятная запись превратилась бы в пустышку
  (см. docs/JOURNAL_RETENTION_ARCHITECTURE.md, 5.2).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Автоматические вехи — то, что движок ставит сам по значимым событиям.
  @auto_kinds ~w(hero_created generation_shift level_threshold skill_threshold
                 first_kill rare_loot quest_completed guild_joined guild_lead
                 social_landmark death_respawn)

  # Избранное игрока — отдельная категория со своим cap.
  @kinds @auto_kinds ++ ~w(bookmark)

  def auto_kinds, do: @auto_kinds
  def kinds, do: @kinds

  schema "hero_milestones" do
    field :kind, :string
    field :source, :string, default: "auto"
    field :entry_type, :string
    field :title, :string
    field :text, :string, default: ""
    field :game_day, :integer
    field :chapter, :integer
    field :payload, :map, default: %{}

    belongs_to :hero, TesIdle.Schemas.Hero

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(milestone, attrs) do
    milestone
    |> cast(attrs, [:hero_id, :kind, :source, :entry_type, :title, :text, :game_day, :chapter, :payload])
    |> validate_required([:hero_id, :kind, :title])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:source, ~w(auto bookmark))
    |> validate_length(:title, max: 160)
    |> foreign_key_constraint(:hero_id)
  end
end

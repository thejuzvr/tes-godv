defmodule TesIdle.Schemas.HeroDailyStat do
  @moduledoc """
  Суточный агрегат героя (UTC). Переживает удаление текстов хроники.

  Идемпотентность держит уникальный индекс `(hero_id, day)` плюс upsert:
  повторная доставка события не удваивает счётчики, позднее событие
  обновляет нужный день, а не теряется.

  `coverage` честно различает агрегат, собранный вживую (`live`), и
  восстановленный backfill'ом из журнала (`backfill`) — у второго могут
  быть пробелы, если часть текстов уже удалена.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @schema_version 1

  # Поля, которые накапливаются сложением.
  @counter_fields ~w(game_events published_entries suppressed_entries victories
                     defeats quests_completed xp_gained gold_gained deaths level_ups)a

  def counter_fields, do: @counter_fields
  def schema_version, do: @schema_version

  schema "hero_daily_stats" do
    field :day, :date
    field :game_events, :integer, default: 0
    field :published_entries, :integer, default: 0
    field :suppressed_entries, :integer, default: 0
    field :victories, :integer, default: 0
    field :defeats, :integer, default: 0
    field :quests_completed, :integer, default: 0
    field :xp_gained, :integer, default: 0
    field :gold_gained, :integer, default: 0
    field :deaths, :integer, default: 0
    field :level_ups, :integer, default: 0
    field :schema_version, :integer, default: @schema_version
    field :coverage, :string, default: "live"
    field :updated_at, :naive_datetime

    belongs_to :hero, TesIdle.Schemas.Hero
  end

  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [:hero_id, :day, :coverage, :schema_version | @counter_fields])
    |> validate_required([:hero_id, :day])
    |> validate_inclusion(:coverage, ~w(live backfill))
    |> foreign_key_constraint(:hero_id)
  end
end

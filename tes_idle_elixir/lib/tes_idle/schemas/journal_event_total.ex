defmodule TesIdle.Schemas.JournalEventTotal do
  @moduledoc """
  Сквозной счётчик событий по герою и типу: сколько создано, сколько
  опубликовано текстом, сколько подавлено троттлингом.

  Нужен, чтобы после очистки хроники показатели «создано за всё время»
  не подменялись числом физически оставшихся строк
  (docs/JOURNAL_RETENTION_ARCHITECTURE.md, раздел 7).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "journal_event_totals" do
    field :entry_type, :string
    field :category, :string, default: "ambient"
    field :created_count, :integer, default: 0
    field :published_count, :integer, default: 0
    field :suppressed_count, :integer, default: 0
    field :first_seen_at, :naive_datetime
    field :last_seen_at, :naive_datetime
    field :updated_at, :naive_datetime

    belongs_to :hero, TesIdle.Schemas.Hero
  end

  def changeset(total, attrs) do
    total
    |> cast(attrs, [
      :hero_id,
      :entry_type,
      :category,
      :created_count,
      :published_count,
      :suppressed_count,
      :first_seen_at,
      :last_seen_at
    ])
    |> validate_required([:hero_id, :entry_type])
    |> foreign_key_constraint(:hero_id)
  end
end

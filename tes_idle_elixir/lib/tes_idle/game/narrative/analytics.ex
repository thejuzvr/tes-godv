defmodule TesIdle.Game.Narrative.Analytics do
  @moduledoc """
  A-2: нарративная аналитика из journal_entries и narrative_templates.
  Чистые read-only запросы — ничего не пишет.
  """

  alias TesIdle.Repo
  alias TesIdle.Schemas.{JournalEntry, NarrativeTemplate}
  import Ecto.Query

  @doc "Использование типов журнала за N дней (сортировка тонкие-первыми): count, средняя длина текста, последний раз."
  def type_usage(days \\ 30) do
    from(j in JournalEntry,
      where: j.created_at >= ^since(days),
      group_by: j.entry_type,
      select: %{
        entry_type: j.entry_type,
        count: count(j.id),
        avg_length: fragment("round(avg(char_length(?)))::int", j.text),
        last_seen: max(j.created_at)
      },
      order_by: [asc: count(j.id), asc: j.entry_type]
    )
    |> Repo.all()
  end

  @doc "Объём записей по дням за N дней (для мини-графика)."
  def daily_volume(days \\ 14) do
    from(j in JournalEntry,
      where: j.created_at >= ^since(days),
      group_by: fragment("date_trunc('day', ?)", j.created_at),
      select: %{
        day: fragment("date_trunc('day', ?)", j.created_at),
        count: count(j.id)
      },
      order_by: [asc: fragment("date_trunc('day', ?)", j.created_at)]
    )
    |> Repo.all()
  end

  @doc "Мёртвые шаблоны: активные template_type без единой записи журнала за N дней."
  def unused_template_types(days \\ 30) do
    used =
      from(j in JournalEntry,
        where: j.created_at >= ^since(days),
        distinct: true,
        select: j.entry_type
      )
      |> Repo.all()

    from(t in NarrativeTemplate,
      where: t.is_active == true,
      distinct: true,
      select: t.template_type
    )
    |> Repo.all()
    |> Enum.reject(&(&1 in used))
    |> Enum.sort()
  end

  @doc "Сводка за N дней: записи, герои, типы."
  def totals(days \\ 30) do
    from(j in JournalEntry,
      where: j.created_at >= ^since(days),
      select: %{
        total: count(j.id),
        heroes: count(j.hero_id, :distinct),
        types: count(j.entry_type, :distinct)
      }
    )
    |> Repo.one()
    |> Map.put(:days, days)
  end

  @doc "Цели для фабрики кандидатов: тонкие типы журнала (< 5 записей) + мёртвые шаблоны, uniq, сортированные."
  def factory_targets(days \\ 30) do
    thin =
      type_usage(days)
      |> Enum.filter(&(&1.count < 5))
      |> Enum.map(& &1.entry_type)

    (thin ++ unused_template_types(days))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp since(days), do: DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
end

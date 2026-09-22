defmodule TesIdleWeb.Admin.StatsController do
  @moduledoc """
  «Пульс мира» — сводка состояния владения для первой вкладки админки.

  Никаких заглушек: все числа считаются по живым таблицам. Модуль отдаёт
  не только тоталы, но и разрезы, из которых фронт рисует график:
  распределение по состояниям, уровни, экономику журнала и активность по дням.
  """

  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Guild, Hero, InventoryItem, Item, JournalEntry, Location, Monster, NarrativeTemplate, Quest, User}
  import Ecto.Query

  @activity_days 14

  def index(conn, params) do
    days = days_param(params)

    json(conn, %{
      totals: totals(),
      heroes: hero_breakdown(),
      levels: level_distribution(),
      economy: economy(days),
      activity: daily_activity(days),
      content: content_breakdown(),
      online: online_snapshot(),
      server_time: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  # ─── Тоталы ──────────────────────────────────────────

  defp totals do
    %{
      users: count(User),
      heroes: count(Hero),
      journal_entries: count(JournalEntry),
      narrative_templates: count(NarrativeTemplate),
      active_templates: Repo.one(from t in NarrativeTemplate, where: t.is_active == true, select: count(t.id)),
      monsters: count(Monster),
      active_monsters: Repo.one(from m in Monster, where: m.is_active == true, select: count(m.id)),
      items: count(Item),
      locations: count(Location),
      quests: count(Quest),
      guilds: count(Guild),
      inventory_rows: count(InventoryItem)
    }
  end

  defp count(schema), do: Repo.one(from x in schema, select: count(x.id))

  # ─── Герои: состояния и здоровье мира ────────────────

  defp hero_breakdown do
    by_state =
      Repo.all(
        from h in Hero,
          group_by: h.state,
          select: %{state: h.state, count: count(h.id)},
          order_by: [desc: count(h.id)]
      )

    %{
      by_state: by_state,
      online: Repo.one(from h in Hero, where: h.is_online == true, select: count(h.id)),
      dead: Repo.one(from h in Hero, where: h.state == "dead", select: count(h.id)),
      jailed: Repo.one(from h in Hero, where: h.state == "jailed", select: count(h.id)),
      avg_level: round_one(Repo.one(from h in Hero, select: avg(h.level))),
      max_level: Repo.one(from h in Hero, select: max(h.level)) || 0,
      total_gold: Repo.one(from h in Hero, select: coalesce(sum(h.gold), 0)) || 0,
      total_kills: Repo.one(from h in Hero, select: coalesce(sum(h.total_kills), 0)) || 0,
      avg_mood: round_one(Repo.one(from h in Hero, select: avg(h.mood))),
      avg_hunger: round_one(Repo.one(from h in Hero, select: avg(h.hunger))),
      avg_fatigue: round_one(Repo.one(from h in Hero, select: avg(h.fatigue)))
    }
  end

  defp level_distribution do
    # Полосы уровней: новички / середина / ветераны. Пустые полосы остаются
    # в ответе с нулём — фронт рисует стабильную шкалу.
    bounds = [{"1–5", 1, 5}, {"6–10", 6, 10}, {"11–20", 11, 20}, {"21–40", 21, 40}, {"41+", 41, 10_000}]

    rows =
      Repo.all(
        from h in Hero,
          select: {h.level, count(h.id)},
          group_by: h.level
      )
      |> Map.new()

    Enum.map(bounds, fn {label, lo, hi} ->
      total = rows |> Enum.filter(fn {level, _} -> level >= lo and level <= hi end) |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      %{label: label, count: total}
    end)
  end

  # ─── Экономика журнала ───────────────────────────────

  defp economy(days) do
    since = since(days)

    from(j in JournalEntry,
      where: j.created_at >= ^since,
      select: %{
        xp: coalesce(sum(j.xp_gained), 0),
        gold: coalesce(sum(j.gold_gained), 0),
        entries: count(j.id),
        heroes: count(j.hero_id, :distinct)
      }
    )
    |> Repo.one()
  end

  # ─── Активность по дням ──────────────────────────────

  defp daily_activity(days) do
    since = since(days)

    rows =
      Repo.all(
        from j in JournalEntry,
          where: j.created_at >= ^since,
          group_by: fragment("date_trunc('day', ?)", j.created_at),
          order_by: [asc: fragment("date_trunc('day', ?)", j.created_at)],
          select: %{
            day: fragment("date_trunc('day', ?)", j.created_at),
            entries: count(j.id),
            heroes: count(j.hero_id, :distinct),
            xp: coalesce(sum(j.xp_gained), 0),
            gold: coalesce(sum(j.gold_gained), 0)
          }
      )

    # Дни без записей должны быть видны как нули, а не как разрыв графика.
    fill_days(rows, days)
  end

  defp fill_days(rows, days) do
    by_date = Map.new(rows, fn row -> {NaiveDateTime.to_date(row.day), row} end)
    today = Date.utc_today()

    for offset <- (days - 1)..0//-1 do
      date = Date.add(today, -offset)

      case Map.get(by_date, date) do
        nil -> %{date: Date.to_iso8601(date), entries: 0, heroes: 0, xp: 0, gold: 0}
        row -> %{row | day: nil} |> Map.put(:date, Date.to_iso8601(date)) |> Map.delete(:day)
      end
    end
  end

  # ─── Контент ─────────────────────────────────────────

  defp content_breakdown do
    %{
      journal_types:
        Repo.all(
          from j in JournalEntry,
            group_by: j.entry_type,
            select: %{entry_type: j.entry_type, count: count(j.id)},
            order_by: [desc: count(j.id)],
            limit: 8
        ),
      locations_by_type:
        Repo.all(
          from l in Location,
            group_by: l.location_type,
            select: %{location_type: l.location_type, count: count(l.id)},
            order_by: [desc: count(l.id)]
        ),
      monsters_by_location:
        Repo.all(
          from m in Monster,
            join: l in Location,
            on: l.id == m.location_id,
            group_by: l.name,
            select: %{location: l.name, count: count(m.id)},
            order_by: [desc: count(m.id)],
            limit: 6
        )
    }
  end

  # ─── Онлайн ──────────────────────────────────────────

  defp online_snapshot do
    %{
      users_online:
        Repo.one(from u in User, where: u.is_online == true, select: count(u.id)) || 0,
      seen_last_hour:
        Repo.one(
          from u in User,
            where: u.last_seen >= ^NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second),
            select: count(u.id)
        ) || 0
    }
  end

  # ─── Хелперы ─────────────────────────────────────────

  defp since(days), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -days * 86_400, :second)

  defp days_param(%{"days" => value}) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n in 1..365 -> n
      _ -> @activity_days
    end
  end

  defp days_param(_), do: @activity_days

  # Postgres avg() по integer-колонке возвращает numeric → Ecto отдаёт Decimal,
  # поэтому приводим явно: и Decimal, и float, и integer.
  defp round_one(nil), do: 0.0
  defp round_one(%Decimal{} = value), do: value |> Decimal.to_float() |> Float.round(2)
  defp round_one(value) when is_float(value), do: Float.round(value, 2)
  defp round_one(value) when is_integer(value), do: value * 1.0
end

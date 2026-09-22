defmodule TesIdleWeb.JournalController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, JournalEntry}
  import Ecto.Query

  @default_limit 50
  @max_limit 200

  @doc """
  Лента хроники героя.

  Курсорная пагинация (`cursor`) вместо глубокого OFFSET: при десятках тысяч
  записей OFFSET заставляет Postgres перебирать и отбрасывать строки, а
  устойчивый курсор `(created_at, id)` листает по индексу
  `(hero_id, created_at DESC, id DESC)`.

  `offset` сохранён для обратной совместимости со старым фронтом.
  """
  def index(conn, params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)

    # `if do:` не прерывает функцию: halt() только помечает conn, а код ниже
    # всё равно обращается к hero.id и роняет запрос 500.
    if is_nil(hero) do
      conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})
    else
      render_index(conn, hero, params)
    end
  end

  defp render_index(conn, hero, params) do
    limit = parse_int(params["limit"], @default_limit) |> min(@max_limit) |> max(1)
    entry_type = Map.get(params, "entry_type")

    base = from je in JournalEntry, where: je.hero_id == ^hero.id
    base = if entry_type, do: from(je in base, where: je.entry_type == ^entry_type), else: base

    # Берём на одну запись больше лимита: наличие лишней строки честно
    # сообщает о следующей странице без дорогого COUNT.
    query =
      base
      |> order_by([je], desc: je.created_at, desc: je.id)
      |> limit(^(limit + 1))

    query =
      case cursor(params["cursor"]) do
        nil ->
          # Обратная совместимость: старый offset-режим.
          case parse_int(params["offset"], 0) do
            offset when offset > 0 -> from(je in query, offset: ^offset)
            _ -> query
          end

        {created_at, id} ->
          from(je in query,
            where:
              je.created_at < ^created_at or
                (je.created_at == ^created_at and je.id < ^id)
          )
      end

    rows = Repo.all(query)
    has_more = length(rows) > limit
    entries = Enum.take(rows, limit)
    last = List.last(entries)

    json(conn, %{
      entries: Enum.map(entries, &entry_json/1),
      has_more: has_more,
      limit: limit,
      next_cursor: if(has_more and last, do: encode_cursor(last), else: nil),
      entry_type: entry_type
    })
  end

  @doc """
  Итоги отсутствия: что случилось с героем, пока игрок не смотрел.

  Ноль строк в хронике не означает отсутствие прогресса — часть событий
  могла быть подавлена троттлингом, а прогресс всё равно применён.
  Поэтому отдаём и счётчики, и последние записи.
  """
  def summary(conn, _params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)

    if is_nil(hero) do
      conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})
    else
      render_summary(conn, hero)
    end
  end

  defp render_summary(conn, hero) do
    since = NaiveDateTime.add(NaiveDateTime.utc_now(), -7 * 86_400, :second)

    recent = Repo.one(
      from je in JournalEntry,
        where: je.hero_id == ^hero.id and je.created_at >= ^since,
        select: %{
          entries: count(je.id),
          xp: coalesce(sum(je.xp_gained), 0),
          gold: coalesce(sum(je.gold_gained), 0)
        }
    )

    json(conn, %{
      totals: TesIdle.Game.Journal.Aggregator.totals_for(hero.id),
      week: normalize(recent),
      milestones: TesIdle.Game.Journal.Milestones.count(hero.id)
    })
  end

  def count(conn, _params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)

    if is_nil(hero) do
      conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})
    else
      render_count(conn, hero)
    end
  end

  defp render_count(conn, hero) do
    total = Repo.one(from je in JournalEntry, where: je.hero_id == ^hero.id, select: count(je.id))

    # «Создано за всё время» берём из сквозных счётчиков: после очистки
    # число физически оставшихся строк меньше числа созданных событий.
    json(conn, %{count: total, totals: TesIdle.Game.Journal.Aggregator.totals_for(hero.id)})
  end

  # ─── Хелперы ─────────────────────────────────────────

  defp entry_json(e) do
    %{
      id: e.id,
      entry_type: e.entry_type,
      text: e.text,
      xp_gained: e.xp_gained,
      gold_gained: e.gold_gained,
      item_name: e.item_name,
      monster_name: e.monster_name,
      location_name: e.location_name,
      created_at: e.created_at,
      chapter: e.chapter,
      chapter_title: e.chapter_title,
      motive: e.motive
    }
  end

  # Курсор кодируем как "created_at|id" — он не подписан, потому что не даёт
  # доступа ни к чему, кроме собственной ленты героя.
  defp encode_cursor(entry) do
    "#{NaiveDateTime.to_iso8601(entry.created_at)}|#{entry.id}"
  end

  defp cursor(nil), do: nil
  defp cursor(""), do: nil

  defp cursor(value) when is_binary(value) do
    case String.split(value, "|", parts: 2) do
      [at, id] ->
        with {:ok, naive} <- NaiveDateTime.from_iso8601(at),
             {:ok, uuid} <- Ecto.UUID.cast(id) do
          {naive, uuid}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp cursor(_), do: nil

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n
      _ -> default
    end
  end

  defp normalize(nil), do: %{entries: 0, xp: 0, gold: 0}

  defp normalize(row) do
    Map.new(row, fn
      {k, %Decimal{} = v} -> {k, decimal_to_int(v)}
      other -> other
    end)
  end

  # sum() по bigint приходит Decimal. to_integer/1 падает, если у значения
  # есть дробная часть — для счётчиков xp/gold это давало 500.
  defp decimal_to_int(%Decimal{} = value) do
    value |> Decimal.round(0) |> Decimal.to_integer()
  end
end

defmodule TesIdle.Game.Journal.Aggregator do
  @moduledoc """
  Идемпотентный учёт событий хроники (docs/JOURNAL_RETENTION_ARCHITECTURE.md, 7).

  Модуль пишет две вещи:

  - `journal_event_totals` — сквозные счётчики «создано/опубликовано/подавлено»
    по герою и типу. Нужны, чтобы после очистки хроники показатели
    «за всё время» не подменялись числом оставшихся строк.
  - `hero_daily_stats` — суточный агрегат, который переживает удаление текстов.

  Идемпотентность обеспечивает upsert по уникальным индексам
  `(hero_id, entry_type)` и `(hero_id, day)`: ретрай не удваивает счётчики,
  а позднее событие обновляет нужный день, а не теряется.

  Все функции наблюдательные: сбой учёта не должен ронять тик героя
  (паттерн из `Brain.Audit`).
  """

  require Logger

  import Ecto.Query

  alias TesIdle.Game.Journal.Classifier
  alias TesIdle.Repo
  alias TesIdle.Schemas.{HeroDailyStat, JournalEventTotal}

  @doc """
  Записывает факт события: оно случилось и было опубликовано текстом.

  `opts`: `:at` (NaiveDateTime, по умолчанию сейчас), `:day` (Date),
  `:deltas` (счётчики агрегата, например `%{victories: 1, xp_gained: 12}`).
  """
  def record_published(hero_id, entry_type, result \\ nil, opts \\ []) do
    category = Classifier.classify(entry_type, result)

    safe(fn ->
      bump_totals(hero_id, entry_type, category, :published, opts)
      bump_daily(hero_id, entry_type, category, opts)
    end)
  end

  @doc "Записывает факт события, текст которого был подавлен троттлингом."
  def record_suppressed(hero_id, entry_type, result \\ nil, opts \\ []) do
    category = Classifier.classify(entry_type, result)

    safe(fn ->
      bump_totals(hero_id, entry_type, category, :suppressed, opts)
      bump_daily(hero_id, entry_type, category, opts, suppressed?: true)
    end)
  end

  @doc """
  Помечает агрегат как восстановленный backfill'ом.

  Backfill из журнала — историческое покрытие: часть текстов могла быть
  удалена раньше, поэтому честно помечаем `coverage: "backfill"`, а не
  выдаём его за живой учёт.
  """
  def mark_backfill(hero_id, day) do
    safe(fn ->
      from(s in HeroDailyStat, where: s.hero_id == ^hero_id and s.day == ^day)
      |> Repo.update_all(set: [coverage: "backfill", updated_at: now()])
    end)
  end

  @doc "Сквозные суммы по герою: создано, опубликовано, подавлено."
  def totals_for(hero_id) do
    row =
      Repo.one(
        from t in JournalEventTotal,
          where: t.hero_id == ^hero_id,
          select: %{
            created: coalesce(sum(t.created_count), 0),
            published: coalesce(sum(t.published_count), 0),
            suppressed: coalesce(sum(t.suppressed_count), 0)
          }
      )

    # sum() по bigint возвращает numeric → Ecto отдаёт Decimal; приводим к целому,
    # иначе сравнения и арифметика на стороне вызывающего кода ломаются.
    normalize_counts(row) || %{created: 0, published: 0, suppressed: 0}
  end

  @doc "Разбивка по типам: где именно рождается объём."
  def by_type(hero_id) do
    Repo.all(
      from t in JournalEventTotal,
        where: t.hero_id == ^hero_id,
        order_by: [desc: t.created_count],
        select: %{
          entry_type: t.entry_type,
          category: t.category,
          created: t.created_count,
          published: t.published_count,
          suppressed: t.suppressed_count,
          last_seen_at: t.last_seen_at
        }
    )
  end

  @doc """
  Сводка по всем героям за период — источник для «Пульса мира» после очистки.

  Уникальных героев считаем `count(distinct hero_id)`, а не суммой дневных
  уникальных значений (это классическая ошибка, см. документ 5.3).
  """
  def summary(from_day, to_day) do
    Repo.one(
      from s in HeroDailyStat,
        where: s.day >= ^from_day and s.day <= ^to_day,
        select: %{
          hero_days: count(s.id),
          heroes: count(s.hero_id, :distinct),
          game_events: coalesce(sum(s.game_events), 0),
          published: coalesce(sum(s.published_entries), 0),
          suppressed: coalesce(sum(s.suppressed_entries), 0),
          victories: coalesce(sum(s.victories), 0),
          defeats: coalesce(sum(s.defeats), 0),
          quests: coalesce(sum(s.quests_completed), 0),
          xp: coalesce(sum(s.xp_gained), 0),
          gold: coalesce(sum(s.gold_gained), 0),
          deaths: coalesce(sum(s.deaths), 0),
          level_ups: coalesce(sum(s.level_ups), 0)
        }
    )
    |> normalize_counts()
  end

  @doc "Агрегат по дням для графика «Пульса мира» (переживает удаление raw)."
  def daily(from_day, to_day) do
    Repo.all(
      from s in HeroDailyStat,
        where: s.day >= ^from_day and s.day <= ^to_day,
        group_by: s.day,
        order_by: [asc: s.day],
        select: %{
          day: s.day,
          heroes: count(s.hero_id, :distinct),
          game_events: coalesce(sum(s.game_events), 0),
          published: coalesce(sum(s.published_entries), 0),
          suppressed: coalesce(sum(s.suppressed_entries), 0),
          victories: coalesce(sum(s.victories), 0),
          defeats: coalesce(sum(s.defeats), 0),
          quests: coalesce(sum(s.quests_completed), 0),
          deaths: coalesce(sum(s.deaths), 0),
          level_ups: coalesce(sum(s.level_ups), 0),
          xp: coalesce(sum(s.xp_gained), 0),
          gold: coalesce(sum(s.gold_gained), 0)
        }
    )
    |> Enum.map(&normalize_counts/1)
  end

  @doc """
  Backfill дневного агрегата из сохранившихся текстов хроники.

  Идемпотентен: счётчики заменяются, а не накапливаются, поэтому повторный
  прогон не удваивает цифры. Помечает день как `backfill`.
  """
  def backfill_day(day) do
    rows =
      Repo.all(
        from j in TesIdle.Schemas.JournalEntry,
          where: fragment("date_trunc('day', ?)::date", j.created_at) == ^day,
          group_by: [j.hero_id],
          select: %{
            hero_id: j.hero_id,
            entries: count(j.id),
            xp: coalesce(sum(j.xp_gained), 0),
            gold: coalesce(sum(j.gold_gained), 0)
          }
      )

    Enum.each(rows, fn row ->
      upsert_daily(row.hero_id, day, %{
        game_events: row.entries,
        published_entries: row.entries,
        xp_gained: row.xp,
        gold_gained: row.gold,
        coverage: "backfill"
      })
    end)

    length(rows)
  end

  # ─── Внутреннее ──────────────────────────────────────

  defp bump_totals(hero_id, entry_type, category, action, opts) do
    created = Keyword.get(opts, :created_delta, 1)
    at = Keyword.get(opts, :at) || now()

    {published, suppressed} =
      case action do
        :published -> {1, 0}
        :suppressed -> {0, 1}
      end

    category = to_string(category)

    # Инкременты считает Postgres: ретрай не удваивает сквозные счётчики
    # даже при гонке. `fragment` здесь работает, потому что запрос собран
    # макросом `from/2` с литеральным списком полей (их набор фиксирован
    # схемой JournalEventTotal).
    conflict =
      from(t in JournalEventTotal,
        update: [
          set: [
            category: ^category,
            created_count: t.created_count + ^created,
            published_count: t.published_count + ^published,
            suppressed_count: t.suppressed_count + ^suppressed,
            last_seen_at: fragment("GREATEST(?, ?)", t.last_seen_at, ^at),
            updated_at: ^at
          ]
        ]
      )

    Repo.insert!(
      %JournalEventTotal{
        hero_id: hero_id,
        entry_type: entry_type,
        category: category,
        created_count: created,
        published_count: published,
        suppressed_count: suppressed,
        first_seen_at: at,
        last_seen_at: at,
        updated_at: at
      },
      on_conflict: conflict,
      conflict_target: [:hero_id, :entry_type]
    )
  end

  defp bump_daily(hero_id, _entry_type, _category, opts, suppressed? \\ false) do
    day = Keyword.get(opts, :day) || Date.utc_today()
    deltas = Keyword.get(opts, :deltas) || %{}

    base = %{
      game_events: 1,
      published_entries: if(suppressed?, do: 0, else: 1),
      suppressed_entries: if(suppressed?, do: 1, else: 0)
    }

    # Дополнительные счётчики события: победа, опыт, золото, уровень…
    deltas =
      deltas
      |> Map.take(HeroDailyStat.counter_fields())
      |> Map.new(fn {k, v} -> {k, v || 0} end)

    upsert_daily(hero_id, day, Map.merge(base, deltas))
  end

  # Upsert с динамическим набором полей.
  #
  # Ecto принимает on_conflict только как query (фрагменты с литеральными
  # полями) — а состав счётчиков зависит от события. Поэтому делаем это
  # явно и предсказуемо: INSERT ... ON CONFLICT DO NOTHING, затем UPDATE
  # инкрементами, если строка уже была. Обе операции в транзакции, поэтому
  # конкурентные вставки не теряют данные.
  #
  # Имена колонок берутся ТОЛЬКО из allowlist схемы (`HeroDailyStat.counter_fields/0`),
  # значения передаются параметрами — подстановка в SQL безопасна.
  defp upsert_daily(hero_id, day, counters) do
    counters = Map.take(counters, HeroDailyStat.counter_fields() ++ [:coverage])

    row =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          hero_id: hero_id,
          day: day,
          schema_version: HeroDailyStat.schema_version(),
          coverage: "live",
          updated_at: now()
        },
        counters
      )

    Repo.transaction(fn ->
      {inserted, _} =
        Repo.insert_all(HeroDailyStat, [row], on_conflict: :nothing, conflict_target: [:hero_id, :day])

      if inserted == 0 do
        apply_daily_update(hero_id, day, counters)
      end
    end)
  end

  defp apply_daily_update(hero_id, day, counters) do
    backfill? = Map.get(counters, :coverage) == "backfill"

    fields =
      counters
      |> Map.keys()
      |> Enum.filter(&(&1 in HeroDailyStat.counter_fields()))

    # При backfill счётчики ЗАМЕНЯЮТСЯ (иначе повторный прогон удвоит цифры),
    # при живой записи — складываются. Инкременты считает Postgres.
    assignments =
      Enum.map_join(fields, ", ", fn field ->
        if backfill? do
          "#{field} = EXCLUDED.#{field}"
        else
          "#{field} = target.#{field} + EXCLUDED.#{field}"
        end
      end)

    suffix = if assignments == "", do: "", else: ", " <> assignments

    sql = """
    UPDATE hero_daily_stats AS target
       SET coverage = EXCLUDED.coverage, updated_at = NOW()#{suffix}
      FROM (SELECT $1::uuid AS hero_id, $2::date AS day, $3::varchar AS coverage#{values_sql(fields, 4)}) AS EXCLUDED
     WHERE target.hero_id = EXCLUDED.hero_id AND target.day = EXCLUDED.day
    """

    params =
      [Ecto.UUID.dump!(hero_id), day, Map.get(counters, :coverage, "live")] ++
        Enum.map(fields, &Map.get(counters, &1, 0))

    Repo.query!(sql, params)
  end

  defp values_sql([], _start), do: ""

  defp values_sql(fields, start) do
    fields
    |> Enum.with_index(start)
    |> Enum.map_join("", fn {field, idx} -> ", $#{idx}::bigint AS #{field}" end)
  end

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  # Postgres sum()/count() по bigint приходят как numeric → Ecto.Decimal.
  # Для JSON и арифметики приводим все числовые поля к integer.
  defp normalize_counts(nil), do: nil

  defp normalize_counts(row) when is_map(row) do
    Map.new(row, fn
      {key, %Decimal{} = value} -> {key, decimal_to_int(value)}
      {key, value} -> {key, value}
    end)
  end

  defp decimal_to_int(%Decimal{} = value) do
    value |> Decimal.round(0) |> Decimal.to_integer()
  end

  # Учёт наблюдательный: его сбой не должен ронять тик героя.
  defp safe(fun) do
    fun.()
    :ok
  rescue
    error ->
      Logger.warning("journal aggregator failed: #{Exception.message(error)}")
      :ok
  catch
    kind, reason ->
      Logger.warning("journal aggregator #{kind}: #{inspect(reason)}")
      :ok
  end
end

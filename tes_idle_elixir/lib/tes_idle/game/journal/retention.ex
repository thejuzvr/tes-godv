defmodule TesIdle.Game.Journal.Retention do
  @moduledoc """
  Очистка обычной хроники (docs/JOURNAL_RETENTION_ARCHITECTURE.md, 5.1 и 8).

  Политика: обычные тексты старше `routine_days` удаляются, НО последние
  `keep_last_routine` обычных записей героя сохраняются независимо от возраста —
  редкий игрок не должен возвращаться к пустому дневнику.

  Всё, что классифицировано как `:important` или `:milestone`, не удаляется
  никогда. Памятные вехи живут в отдельной таблице и переживают очистку.

  Безопасность (раздел 8):

  - пакетами с ограниченным размером, чтобы не блокировать игровые тики;
  - `dry_run` по умолчанию — сначала показываем, что будет удалено;
  - lease-блокировка: два узла не чистят одновременно;
  - лимит длительности прогона;
  - результат репортится числами, а не «выполнено успешно».

  Воркер намеренно НЕ удаляет `world_news` и `dream`: это тоже фон, но он
  редкий и связывает героя с миром. Их подавляет троттлинг, а не retention.
  """

  require Logger

  import Ecto.Query

  alias TesIdle.Game.Journal.Classifier
  alias TesIdle.Repo
  alias TesIdle.Schemas.JournalEntry

  @default_days 7
  @default_keep_last 500
  @default_batch_size 1000
  @default_max_seconds 120
  @lock_key 7_412_003
  @protected_types Classifier.protected_types() ++ ~w(dream world_news)

  def default_config do
    %{
      "enabled" => false,
      "dry_run" => true,
      "routine_days" => @default_days,
      "keep_last_routine" => @default_keep_last,
      "warning_rows_per_hero" => 10_000,
      "batch_size" => @default_batch_size
    }
  end

  @doc "Настройки политики: дефолты + значения из game_configs."
  def config(configs \\ %{}) do
    raw = get_in(configs || %{}, ["journal_retention"]) || %{}
    defaults = default_config()

    %{
      enabled: bool(raw["enabled"], defaults["enabled"]),
      dry_run: bool(raw["dry_run"], defaults["dry_run"]),
      routine_days: positive(raw["routine_days"], @default_days),
      keep_last_routine: positive(raw["keep_last_routine"], @default_keep_last),
      warning_rows_per_hero: positive(raw["warning_rows_per_hero"], 10_000),
      batch_size: min(positive(raw["batch_size"], @default_batch_size), 10_000)
    }
  end

  @doc """
  Прогон очистки. Возвращает отчёт:

      %{dry_run: true, candidates: 1234, deleted: 0, heroes: 3, scanned: 5000}

  В dry-run ничего не удаляется, но считается ровно то, что было бы удалено.
  """
  def run(configs \\ %{}, opts \\ []) do
    cfg = config(configs)
    max_seconds = Keyword.get(opts, :max_seconds, @default_max_seconds)

    cond do
      not cfg.enabled ->
        %{skipped: true, reason: :disabled, deleted: 0, candidates: 0}

      not acquire_lock() ->
        # Другой узел уже чистит — не дублируем работу.
        %{skipped: true, reason: :locked, deleted: 0, candidates: 0}

      true ->
        try do
          execute(cfg, max_seconds)
        after
          release_lock()
        end
    end
  end

  @doc """
  Предпросмотр без изменений: сколько строк и по каким типам уйдёт.
  Именно это показывает админка до включения политики.
  """
  def preview(configs \\ %{}) do
    cfg = %{config(configs) | enabled: true, dry_run: true}
    count_candidates(cfg)
  end

  @doc "Строки на героя: предупреждение о разросшемся источнике."
  def oversized_heroes(configs \\ %{}) do
    cfg = config(configs)

    Repo.all(
      from j in JournalEntry,
        group_by: j.hero_id,
        having: count(j.id) > ^cfg.warning_rows_per_hero,
        select: %{hero_id: j.hero_id, rows: count(j.id)},
        order_by: [desc: count(j.id)],
        limit: 50
    )
  end

  # ─── Прогон ──────────────────────────────────────────

  defp execute(cfg, max_seconds) do
    deadline = System.monotonic_time(:second) + max_seconds
    cutoff = cutoff(cfg)

    do_batches(cfg, cutoff, deadline, %{deleted: 0, candidates: 0, heroes: 0, batches: 0})
  end

  defp do_batches(cfg, cutoff, deadline, acc) do
    cond do
      System.monotonic_time(:second) >= deadline ->
        Logger.warning("journal retention hit its time limit; continuing next run")
        Map.put(acc, :timed_out, true)

      true ->
        batch = candidates(cfg, cutoff, cfg.batch_size)

        case batch do
          [] ->
            acc

          rows ->
            heroes = rows |> Enum.map(& &1.hero_id) |> Enum.uniq() |> length()

            deleted =
              if cfg.dry_run do
                0
              else
                ids = Enum.map(rows, & &1.id)
                {count, _} = Repo.delete_all(from j in JournalEntry, where: j.id in ^ids)
                count
              end

            acc = %{
              acc
              | deleted: acc.deleted + deleted,
                candidates: acc.candidates + length(rows),
                heroes: acc.heroes + heroes,
                batches: acc.batches + 1
            }

            if cfg.dry_run do
              # В dry-run считаем кандидатов, но не удаляем: иначе следующий
              # проход вернул бы те же строки и цикл стал бы бесконечным.
              Map.put(acc, :dry_run, true)
            else
              do_batches(cfg, cutoff, deadline, acc)
            end
        end
    end
  end

  # Кандидаты: строка старше cutoff, не защищённого типа и НЕ входит
  # в последние keep_last_routine обычных записей героя.
  #
  # Порядок по (created_at, id) — устойчивый курсор: пакетная выборка
  # не пропускает и не дублирует строки между проходами.
  #
  # Грабля: `limit: 0` в Ecto означает «без ограничения», поэтому хвост
  # сохраняем только при keep_last_routine > 0 — иначе подзапрос вернул бы
  # ВСЕ записи героя и защита превратилась бы в «не удалять ничего».
  defp candidates(cfg, cutoff, limit) do
    protected = @protected_types

    query =
      from(j in JournalEntry, as: :entry,
        where: j.created_at < ^cutoff,
        where: j.entry_type not in ^protected,
        order_by: [asc: j.created_at, asc: j.id],
        limit: ^limit,
        select: %{id: j.id, hero_id: j.hero_id, entry_type: j.entry_type, created_at: j.created_at}
      )

    query
    |> exclude_recent_routine(cfg)
    |> Repo.all()
  end

  defp exclude_recent_routine(query, %{keep_last_routine: keep}) when keep > 0 do
    from(j in query,
      where:
        j.id not in subquery(
          from recent in JournalEntry,
            where: recent.hero_id == parent_as(:entry).hero_id,
            where: recent.entry_type not in ^@protected_types,
            order_by: [desc: recent.created_at, desc: recent.id],
            limit: ^keep,
            select: recent.id
        )
    )
  end

  defp exclude_recent_routine(query, _cfg), do: query

  defp count_candidates(cfg) do
    cutoff = cutoff(cfg)
    protected = @protected_types
    keep = cfg.keep_last_routine

    # Один проход с оконной функцией. Коррелированный NOT IN по каждой строке
    # на живой хронике (~100k строк) не укладывался в таймаут и ронял вкладку
    # «Хроника» 500 ещё до отрисовки.
    # Хвост считается по ВСЕЙ обычной хронике героя, а не только по строкам
    # старше cutoff. Иначе свежие записи вытесняют старые из «последних N»,
    # и предпросмотр завышает число удаляемых.
    sql = """
    SELECT entry_type, count(*)::bigint AS count
      FROM (
        SELECT entry_type, created_at,
               row_number() OVER (
                 PARTITION BY hero_id
                 ORDER BY created_at DESC, id DESC
               ) AS rn
          FROM journal_entries
         WHERE NOT (entry_type = ANY($1))
      ) ranked
     WHERE created_at < $2
       AND ($3::int <= 0 OR rn > $3)
     GROUP BY entry_type
     ORDER BY count DESC
    """

    %{rows: rows} = Repo.query!(sql, [protected, cutoff, keep])

    by_type =
      rows
      |> Enum.map(fn [entry_type, count] ->
        %{entry_type: entry_type, count: decimal_or_int(count)}
      end)
      |> Enum.take(20)

    %{
      dry_run: true,
      cutoff: NaiveDateTime.to_iso8601(cutoff),
      routine_days: cfg.routine_days,
      keep_last_routine: keep,
      candidates: Enum.reduce(by_type, 0, &(&1.count + &2)),
      by_type: by_type
    }
  end

  # ─── Lease ───────────────────────────────────────────

  # Advisory-лок Postgres: узел, взявший его, чистит один. Освобождается
  # автоматически при падении процесса — «залипшего» лока не бывает.
  defp acquire_lock do
    %{rows: [[acquired]]} = Repo.query!("SELECT pg_try_advisory_lock($1)", [@lock_key])
    acquired
  end

  defp release_lock do
    Repo.query!("SELECT pg_advisory_unlock($1)", [@lock_key])
    :ok
  end

  defp cutoff(cfg) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(-cfg.routine_days * 86_400, :second)
    |> NaiveDateTime.truncate(:second)
  end

  # ─── Хелперы ─────────────────────────────────────────

  defp bool(nil, default), do: default
  defp bool(value, _default) when is_boolean(value), do: value
  defp bool("true", _), do: true
  defp bool("false", _), do: false
  defp bool(_, default), do: default

  defp positive(value, _default) when is_integer(value) and value > 0, do: value
  defp positive(value, _default) when is_float(value) and value > 0, do: trunc(value)

  defp positive(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp positive(_value, default), do: default

  defp decimal_or_int(%Decimal{} = value), do: value |> Decimal.round(0) |> Decimal.to_integer()
  defp decimal_or_int(value) when is_integer(value), do: value
  defp decimal_or_int(_), do: 0
end

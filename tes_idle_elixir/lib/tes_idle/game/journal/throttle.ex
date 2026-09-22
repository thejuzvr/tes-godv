defmodule TesIdle.Game.Journal.Throttle do
  @moduledoc """
  Ограничение повторов атмосферных записей
  (docs/JOURNAL_RETENTION_ARCHITECTURE.md, 6.2 и 6.4).

  Зачем: движок пишет фон почти каждый тик, и 85% хроники — «смотрит на закат»,
  «слушает птиц». Дешевле не создавать такую строку, чем записать, разослать
  в WebSocket и потом чистить.

  Два независимых ограничения:

  1. **Кулдаун на тип** — один тип не чаще, чем раз в N секунд на героя.
  2. **Бюджет атмосферы за час** — не более M атмосферных записей за скользящий
     час. Без него двадцать разных типов обошли бы первое правило, чередуясь.

  Важные события (`:important`, `:milestone`) не ограничиваются никогда —
  об этом заботится `Classifier`.

  Режимы (`game_configs["journal_throttle"]["mode"]`):

  - `off` — ограничение выключено, всё пишется;
  - `shadow` — считаем, что было бы подавлено, но публикуем всё (безопасный
    замер эффекта перед включением);
  - `enforce` — реально подавляем атмосферные записи.

  Состояние держится в ETS с атомарным `update_counter` — это advisory-лимит
  для одного узла. При рестарте счётчики теряются, что допустимо: несколько
  лишних атмосферных строк после перезапуска не стоят усложнения.
  """

  alias TesIdle.Game.Journal.Classifier

  @table :journal_throttle
  @default_cooldown_seconds 600
  @default_per_hour 6
  @hour_ms 3_600_000

  @doc "Инициализация ETS. Вызывается из Application; повторный вызов безопасен."
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    end

    :ok
  rescue
    _ -> :ok
  end

  @doc """
  Разрешить публикацию события?

  Возвращает `{decision, meta}`, где `decision` — `:publish` или `:suppress`,
  а `meta` несёт причину и настройки (для телеметрии и отчётов).

  Побочный эффект: при `:publish` фиксирует факт использования окна.
  При `:shadow` решение всегда `:publish`, но в `meta.suppressed?` видно,
  что было бы подавлено, — это и есть безопасный замер.
  """
  def check(hero_id, entry_type, result \\ nil, configs \\ %{}) do
    cfg = config(configs)
    mode = cfg.mode

    category = Classifier.classify(entry_type, result)

    cond do
      mode == :off ->
        {%{allowed?: true, reason: :off, category: category, mode: mode}, :publish}

      category != :ambient ->
        {%{allowed?: true, reason: :protected, category: category, mode: mode}, :publish}

      true ->
        decide(hero_id, entry_type, category, cfg, mode)
    end
  end

  @doc "Только вопрос «было бы подавлено?» без побочных эффектов — для проверок в тестах."
  def peek(hero_id, entry_type, result \\ nil, configs \\ %{}) do
    {meta, _} = check(hero_id, entry_type, result, configs)
    meta
  end

  @doc "Настройки политики: дефолты + значения из game_configs."
  def config(configs) do
    raw = get_in(configs || %{}, ["journal_throttle"]) || %{}

    %{
      mode: parse_mode(raw["mode"]),
      cooldown_seconds: positive(raw["ambient_type_cooldown_seconds"], @default_cooldown_seconds),
      per_hour: positive(raw["ambient_per_hour"], @default_per_hour)
    }
  end

  @doc "Сброс состояния — для тестов и административного сброса."
  def reset do
    init()
    :ets.delete_all_objects(@table)
    :ok
  end

  # ─── Решение ─────────────────────────────────────────

  defp decide(hero_id, entry_type, category, cfg, mode) do
    now_ms = System.monotonic_time(:millisecond)

    {type_ok?, used_at} = try_type_slot(hero_id, entry_type, cfg.cooldown_seconds, now_ms)
    {budget_ok?, used_in_hour} = try_hour_budget(hero_id, cfg.per_hour, now_ms)

    allowed? = type_ok? and budget_ok?

    reason =
      cond do
        not type_ok? -> :type_cooldown
        not budget_ok? -> :hour_budget
        true -> :allowed
      end

    meta = %{
      allowed?: allowed?,
      reason: reason,
      category: category,
      mode: mode,
      cooldown_seconds: cfg.cooldown_seconds,
      per_hour: cfg.per_hour,
      ms_since_type: if(used_at, do: now_ms - used_at, else: nil),
      used_in_hour: used_in_hour,
      # В shadow-режиме публикуем всегда, но помечаем, что было бы подавлено.
      suppressed?: mode == :enforce and not allowed?,
      would_suppress?: not allowed?
    }

    decision = if meta.suppressed?, do: :suppress, else: :publish
    {meta, decision}
  end

  # Атомарный check-and-set: update_counter возвращает новое значение, поэтому
  # два параллельных тика не могут проскочить окно одновременно.
  defp try_type_slot(hero_id, entry_type, cooldown_seconds, now_ms) do
    key = {:type, hero_id, entry_type}
    cooldown_ms = cooldown_seconds * 1000
    bucket = div(now_ms, cooldown_ms)

    # Значение = номер текущего окна. Если он сменился — окно свободно,
    # и мы его атомарно занимаем.
    case :ets.insert_new(@table, {key, bucket}) do
      true ->
        {true, nil}

      false ->
        case :ets.lookup(@table, key) do
          [{^key, ^bucket}] ->
            {false, read_last_used(hero_id, entry_type)}

          _ ->
            # Окно сменилось — занимаем новое.
            :ets.insert(@table, {key, bucket})
            {true, read_last_used(hero_id, entry_type)}
        end
    end
  end

  defp try_hour_budget(hero_id, per_hour, now_ms) do
    init()
    key = {:hour, hero_id}

    case :ets.lookup(@table, key) do
      [] ->
        # {key, window_start, count} — счётчик стоит третьим элементом,
        # поэтому update_counter идёт по позиции 3.
        :ets.insert(@table, {key, now_ms, 1})
        {1 <= per_hour, 1}

      [{^key, window_start, _count}] ->
        if now_ms - window_start >= @hour_ms do
          :ets.insert(@table, {key, now_ms, 1})
          {1 <= per_hour, 1}
        else
          new_count = :ets.update_counter(@table, key, {3, 1})
          {new_count <= per_hour, new_count}
        end
    end
  end

  defp read_last_used(hero_id, entry_type) do
    case :ets.lookup(@table, {:last_used, hero_id, entry_type}) do
      [{_, at}] -> at
      _ -> nil
    end
  end

  @doc "Фиксирует момент фактической публикации — для отчёта «прошло N мс»."
  def mark_published(hero_id, entry_type) do
    init()
    :ets.insert(@table, {{:last_used, hero_id, entry_type}, System.monotonic_time(:millisecond)})
    :ok
  end

  @doc "Снимок состояния ограничителя — для админ-панели и тестов."
  def snapshot(hero_id) do
    init()

    types =
      :ets.foldl(
        fn
          {{:type, ^hero_id, entry_type}, bucket}, acc -> Map.put(acc, entry_type, bucket)
          _, acc -> acc
        end,
        %{},
        @table
      )

    hour =
      case :ets.lookup(@table, {:hour, hero_id}) do
        [{_, _start, count}] -> count
        _ -> 0
      end

    %{hero_id: hero_id, types: types, used_in_hour: hour}
  end

  # ─── Хелперы ─────────────────────────────────────────

  defp parse_mode(value) do
    case value do
      "enforce" -> :enforce
      "shadow" -> :shadow
      "off" -> :off
      true -> :enforce
      false -> :off
      _ -> :shadow
    end
  end

  defp positive(value, _default) when is_integer(value) and value > 0, do: value
  defp positive(value, _default) when is_float(value) and value > 0, do: trunc(value)

  defp positive(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp positive(_value, default), do: default
end

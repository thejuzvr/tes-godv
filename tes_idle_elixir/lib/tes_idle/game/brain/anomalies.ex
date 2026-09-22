defmodule TesIdle.Game.Brain.Anomalies do
  @moduledoc """
  S-6: детектор аномалий в решениях ИИ героев.

  Модуль **чистый**: принимает уже собранную статистику (см. `AuditStats.analysis/1`)
  и возвращает список аномалий с порогами и подсказками. Никаких Repo-запросов —
  поэтому все правила проверяются обычными unit-тестами без БД.

  Зачем: балансировка Utility AI. Аномалия — это сигнал «мозг работает нештатно»
  (залипание в одной цели, цикл смены намерений, действие, которое всегда падает),
  а не просто «цифра большая». Поэтому у каждой аномалии есть порог и рекомендация.

  Уровни: `:critical` — игра сломана для героя (например, все действия падают),
  `:warning` — перекос, который стоит выровнять весами, `:info` — наблюдение.
  """

  @type severity :: :critical | :warning | :info

  @type anomaly :: %{
          kind: String.t(),
          severity: severity,
          title: String.t(),
          detail: String.t(),
          hint: String.t(),
          goal: String.t() | nil,
          action: String.t() | nil,
          hero: String.t() | nil,
          value: float,
          threshold: float
        }

  # ─── Пороги (все настраиваемые, но с разумными дефолтами) ───

  # Цель забирает почти все решения — веса перекошены в её пользу.
  @goal_concentration_warning 0.60
  @goal_concentration_critical 0.80

  # Намерение меняется слишком часто: герой не доводит дело до конца.
  @switch_rate_warning 0.35
  @switch_rate_critical 0.55

  # Намерение держится слишком долго: герой залип (классический цикл).
  @hold_rate_warning 0.85

  # Действие падает: сначала предупреждение, потом критика.
  @failure_rate_warning 0.25
  @failure_rate_critical 0.50

  # Минимум событий, ниже которого статистика нерепрезентативна.
  @min_events_for_rates 10
  @min_events_per_action 4

  # Разброс полезности: если у целей почти одинаковый utility, выбор случаен.
  @utility_spread_info 0.05

  @doc """
  Основной вход: собирает аномалии по сводке, целям, исходам действий и героям.

  `analysis` — карта с ключами `:totals`, `:intent_by_goal`, `:action_outcomes`, `:heroes`.
  """
  def detect(analysis) when is_map(analysis) do
    totals = Map.get(analysis, :totals) || %{}

    []
    |> add_concentration(analysis, totals)
    |> add_switch_rate(totals)
    |> add_hold_rate(analysis, totals)
    |> add_action_failures(analysis, totals)
    |> add_hero_outliers(analysis, totals)
    |> add_utility_flatness(analysis)
    |> add_dead_goals(analysis, totals)
    |> Enum.sort_by(&severity_rank(&1.severity))
  end

  @doc "Сводка по уровням — для шапки панели и файла выгрузки."
  def summary(anomalies) when is_list(anomalies) do
    %{
      critical: Enum.count(anomalies, &(&1.severity == :critical)),
      warning: Enum.count(anomalies, &(&1.severity == :warning)),
      info: Enum.count(anomalies, &(&1.severity == :info)),
      total: length(anomalies)
    }
  end

  # ─── Правила ─────────────────────────────────────────

  defp add_concentration(acc, analysis, totals) do
    intents = totals[:intents] || 0
    goals = Map.get(analysis, :intent_by_goal) || []

    case goals do
      [top | _] when intents >= @min_events_for_rates ->
        share = count_of(top) / intents
        goal = top.goal

        cond do
          share >= @goal_concentration_critical ->
            [
              anomaly(
                "goal_starvation",
                :critical,
                "Цель «#{goal_label(goal)}» поглощает мозг",
                "#{pct(share)} всех решений (#{count_of(top)} из #{intents}) уходит в одну цель.",
                "Снизьте вес этой цели в Goal.utility или поднимите конкурирующие: сейчас герой не рассматривает альтернативы.",
                goal,
                nil,
                nil,
                share,
                @goal_concentration_critical
              )
              | acc
            ]

          share >= @goal_concentration_warning ->
            [
              anomaly(
                "goal_dominance",
                :warning,
                "Перекос в цель «#{goal_label(goal)}»",
                "#{pct(share)} решений (#{count_of(top)} из #{intents}) — одна цель.",
                "Проверьте веса: вероятно, цель выигрывает за счёт одного сильного слагаемого, а не суммы потребностей.",
                goal,
                nil,
                nil,
                share,
                @goal_concentration_warning
              )
              | acc
            ]

          true ->
            acc
        end

      _ ->
        acc
    end
  end

  defp add_switch_rate(acc, totals) do
    intents = totals[:intents] || 0
    rate = totals[:switch_rate] || 0.0

    cond do
      intents < @min_events_for_rates -> acc
      rate >= @switch_rate_critical ->
        [
          anomaly(
            "intent_thrashing",
            :critical,
            "Мозг мечется между целями",
            "#{pct(rate)} решений — смена намерения при #{intents} решениях.",
            "Увеличьте hysteresis (`switch_margin`) и anti-repeat: герой не успевает довести начатое до конца.",
            nil,
            nil,
            nil,
            rate,
            @switch_rate_critical
          )
          | acc
        ]

      rate >= @switch_rate_warning ->
        [
          anomaly(
            "intent_unstable",
            :warning,
            "Нестабильный выбор цели",
            "#{pct(rate)} решений — смена намерения.",
            "Намерение меняется чаще, чем раз в несколько тиков. Проверьте `switch_margin` и разброс utility между целями.",
            nil,
            nil,
            nil,
            rate,
            @switch_rate_warning
          )
          | acc
        ]

      true ->
        acc
    end
  end

  defp add_hold_rate(acc, analysis, totals) do
    intents = totals[:intents] || 0
    goals = Map.get(analysis, :intent_by_goal) || []

    if intents >= @min_events_for_rates do
      case Enum.max_by(goals, &held_share(&1, intents), fn -> nil end) do
        nil ->
          acc

        goal ->
          share = held_share(goal, intents)

          if share >= @hold_rate_warning and goal.held >= @min_events_for_rates do
            [
              anomaly(
                "intent_stuck",
                :warning,
                "Цель «#{goal_label(goal.goal)}» держится слишком долго",
                "#{pct(share)} событий цели — удержание (#{goal.held} удержаний при #{goal.switched} сменах).",
                "Похоже на цикл: цель удерживается, но не прогрессирует. Проверьте, завершаются ли её действия успехом.",
                goal.goal,
                nil,
                nil,
                share,
                @hold_rate_warning
              )
              | acc
            ]
          else
            acc
          end
      end
    else
      acc
    end
  end

  defp add_action_failures(acc, analysis, totals) do
    actions = Map.get(analysis, :action_outcomes) || []

    acc =
      Enum.reduce(actions, acc, fn row, inner ->
        total = row.completed + row.failed

        if total >= @min_events_per_action and row.failed > 0 do
          rate = row.failed / total

          cond do
            rate >= @failure_rate_critical ->
              [
                anomaly(
                  "action_broken",
                  :critical,
                  "Действие «#{row.action || "—"}» почти всегда падает",
                  "#{row.failed} сбоев из #{total} попыток (#{pct(rate)}), цель «#{goal_label(row.goal)}».",
                  "Действие недостижимо при текущих условиях: проверьте его `execute` (контракт `{:ok, _}`) и требования цели.",
                  row.goal,
                  row.action,
                  nil,
                  rate,
                  @failure_rate_critical
                )
                | inner
              ]

            rate >= @failure_rate_warning ->
              [
                anomaly(
                  "action_fragile",
                  :warning,
                  "Действие «#{row.action || "—"}» часто не удаётся",
                  "#{row.failed} сбоев из #{total} (#{pct(rate)}).",
                  "Стоит проверить предпосылки действия (локация, ресурсы, состояние героя).",
                  row.goal,
                  row.action,
                  nil,
                  rate,
                  @failure_rate_warning
                )
                | inner
              ]

            true ->
              inner
          end
        else
          inner
        end
      end)

    # Отдельно: сбои есть, но действий с достаточной выборкой нет — общий фон.
    if acc == [] and (totals[:failed_actions] || 0) > 0 and (totals[:failure_rate] || 0.0) >= @failure_rate_warning do
      [
        anomaly(
          "global_failure_rate",
          :warning,
          "Много сбоев действий",
          "#{totals[:failed_actions]} сбоев из #{totals[:actions]} действий (#{pct(totals[:failure_rate])}).",
          "Сбои размазаны по действиям без явного лидера — смотрите общий лог и причины в metadata.",
          nil,
          nil,
          nil,
          totals[:failure_rate],
          @failure_rate_warning
        )
        | acc
      ]
    else
      acc
    end
  end

  defp add_hero_outliers(acc, analysis, totals) do
    heroes = Map.get(analysis, :heroes) || []
    total_events = totals[:events] || 0

    if length(heroes) >= 2 and total_events > 0 do
      Enum.reduce(heroes, acc, fn hero, inner ->
        share = hero.events / total_events
        events = hero.selected + hero.held + hero.switched
        switch_rate = if events > 0, do: hero.switched / events, else: 0.0
        failures = hero.failed
        attempts = hero.completed + hero.failed

        cond do
          # Один герой пишет почти весь аудит — возможно, остальные мертвы.
          share >= 0.9 and length(heroes) > 1 ->
            [
              anomaly(
                "hero_silence",
                :warning,
                "#{hero.hero} — единственный, кто действует",
                "#{pct(share)} всех событий аудита (#{hero.events} из #{total_events}) при #{length(heroes)} героях.",
                "Остальные герои молчат: проверьте их состояние (dead/jailed) и что GameTickWorker их обрабатывает.",
                nil,
                nil,
                hero.hero,
                share,
                0.9
              )
              | inner
            ]

          attempts >= @min_events_per_action and failures > 0 and failures / attempts >= @failure_rate_critical ->
            [
              anomaly(
                "hero_broken",
                :critical,
                "У героя #{hero.hero} разваливаются действия",
                "#{failures} сбоев из #{attempts} действий (#{pct(failures / attempts)}).",
                "Проблема локализована в герое: смотрите его state_data (план, jail, law) и последние metadata.",
                nil,
                nil,
                hero.hero,
                failures / attempts,
                @failure_rate_critical
              )
              | inner
            ]

          events >= @min_events_for_rates and switch_rate >= @switch_rate_critical ->
            [
              anomaly(
                "hero_thrashing",
                :warning,
                "Герой #{hero.hero} часто меняет намерение",
                "#{pct(switch_rate)} решений — смена (#{hero.switched} из #{events}).",
                "Проверьте его brain_hash и последние решения: возможен цикл между двумя целями.",
                nil,
                nil,
                hero.hero,
                switch_rate,
                @switch_rate_critical
              )
              | inner
            ]

          true ->
            inner
        end
      end)
    else
      acc
    end
  end

  defp add_utility_flatness(acc, analysis) do
    goals = Map.get(analysis, :intent_by_goal) || []
    utilities = goals |> Enum.map(& &1.avg_utility) |> Enum.reject(&is_nil/1)

    if length(utilities) >= 3 do
      spread = Enum.max(utilities) - Enum.min(utilities)

      if spread <= @utility_spread_info do
        [
          anomaly(
            "utility_flat",
            :info,
            "Полезность целей почти не различается",
            "Разброс средней utility всего #{Float.round(spread, 3)} при #{length(utilities)} целях.",
            "Выбор становится почти случайным. Проверьте, что слагаемые потребностей дают разный вклад, а не сходятся к константе.",
            nil,
            nil,
            nil,
            spread,
            @utility_spread_info
          )
          | acc
        ]
      else
        acc
      end
    else
      acc
    end
  end

  defp add_dead_goals(acc, analysis, totals) do
    goals = Map.get(analysis, :intent_by_goal) || []
    distinct = totals[:distinct_goals] || length(goals)

    # Много целей, но часть из них вообще не выбиралась — веса мертвы.
    never_selected =
      goals
      |> Enum.filter(&(&1.selected == 0 and &1.held == 0 and &1.switched == 0))
      |> Enum.map(&goal_label(&1.goal))

    if never_selected != [] and distinct > 0 do
      [
        anomaly(
          "dead_goals",
          :info,
          "Часть целей не выбирается",
          "#{length(never_selected)} целей без единого решения: #{Enum.join(never_selected, ", ")}.",
          "Либо цели недостижимы при текущих условиях, либо их utility всегда проигрывает. Проверьте условия активации.",
          nil,
          nil,
          nil,
          length(never_selected) * 1.0,
          1.0
        )
        | acc
      ]
    else
      acc
    end
  end

  # ─── Хелперы ─────────────────────────────────────────

  defp count_of(row), do: row.selected + row.held + row.switched

  defp held_share(row, intents) when intents > 0, do: row.held / intents
  defp held_share(_row, _intents), do: 0.0

  defp goal_label(nil), do: "без цели"
  defp goal_label(goal), do: to_string(goal)

  defp pct(share) when is_number(share), do: "#{Float.round(share * 100, 1)}%"
  defp pct(_), do: "0%"

  defp severity_rank(:critical), do: 0
  defp severity_rank(:warning), do: 1
  defp severity_rank(:info), do: 2
  defp severity_rank(_), do: 3

  defp anomaly(kind, severity, title, detail, hint, goal, action, hero, value, threshold) do
    %{
      kind: kind,
      severity: severity,
      title: title,
      detail: detail,
      hint: hint,
      goal: goal,
      action: action,
      hero: hero,
      value: Float.round(value * 1.0, 4),
      threshold: Float.round(threshold * 1.0, 4)
    }
  end
end

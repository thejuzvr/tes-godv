defmodule TesIdle.Game.Brain.Intent do
  @moduledoc """
  S-2: единое ядро решений персонажа.

  Три стадии оценки целей (все чистые, трассируемые):

      1. Goal.base_goals(ctx)     — нужды, характер, память (Utility AI)
      2. Brain.Graph.enrich(ctx)  — причуды и связи (кэп brain.cap, ±0.15)
      3. apply_world(ctx)         — модификаторы ядра мира по характеру
                                    (кэп world_limits.utility_cap, ±0.15)

  Мир влияет на решение, но не решает за героя: цели, отброшенные на
  стадии 1 (utility <= 0), миром не воскрешаются. Каждое влияние оставляет
  reason-trace в brain_reasons — «почему герой так решил» — который
  попадает в decision_log и дальше в дневник (S-3).
  """

  alias TesIdle.Game.{Goal, Personality, Law}

  @intent_defaults %{
    "enabled" => true,
    "switch_margin" => 0.08,
    "min_hold_decisions" => 2,
    "repeat_window" => 5,
    "repeat_penalty" => 0.025,
    "frustration_step" => 0.08,
    "frustration_max" => 0.32,
    "novelty" => 0.0001
  }

  @doc "Полная оценка целей: base → enrich → world → continuity. Отсортировано по выбору."
  def evaluate(ctx) do
    goals =
      ctx
      |> Goal.base_goals()
      |> enrich_stage(ctx)
      |> world_stage(ctx)

    apply_continuity(goals, ctx)
  end

  @doc "Чисто записывает известный исход текущего intent; Pipeline подключит это отдельно."
  def record_outcome(state_data, result, configs) when is_map(state_data) do
    cfg = intent_cfg(configs)

    if cfg["enabled"] == true do
      brain = state_data["brain"] || %{}
      intent = brain["intent"] || %{}
      old = numeric(intent["frustration"], 0.0)

      {frustration, outcome} =
        case outcome_kind(result) do
          :failure -> {min(cfg["frustration_max"], old + cfg["frustration_step"]), "failure"}
          :progress -> {0.0, "progress"}
          :unknown -> {old, "unknown"}
        end

      updated =
        intent
        |> Map.put("frustration", round4(frustration))
        |> Map.put("last_outcome", outcome)

      Map.put(state_data, "brain", Map.put(brain, "intent", updated))
    else
      state_data
    end
  end

  def record_outcome(state_data, _result, _configs), do: state_data

  defp apply_continuity(goals, ctx) do
    cfg = intent_cfg(ctx.configs || %{})

    if cfg["enabled"] != true do
      Enum.sort_by(goals, &(-&1.utility))
    else
      intent = current_intent(ctx.state_data || %{})
      current_name = parse_goal(intent["goal"])
      held = integer(intent["held_decisions"], 0)
      frustration = numeric(intent["frustration"], 0.0)
      recent = recent_goals(ctx.state_data || %{}, cfg["repeat_window"])

      adjusted =
        Enum.map(goals, fn goal ->
          repeats = Enum.count(recent, &(&1 == to_string(goal.name)))
          repeat_delta = repeats * cfg["repeat_penalty"]
          frustration_delta = if goal.name == current_name, do: frustration, else: 0.0
          jitter = stable_jitter(ctx, goal.name, cfg["novelty"])
          delta = jitter - repeat_delta - frustration_delta

          traces =
            []
            |> add_trace(repeat_delta > 0, "анти-повтор: #{repeats} в последних #{cfg["repeat_window"]} (−#{fmt(repeat_delta)})")
            |> add_trace(frustration_delta > 0, "фрустрация текущего намерения (−#{fmt(frustration_delta)})")
            |> add_trace(jitter != 0.0, "детерминированная новизна (#{signed(jitter)})")

          %{goal |
            utility: goal.utility |> Kernel.+(delta) |> max(0.0) |> min(1.0),
            brain_reasons: (goal.brain_reasons || []) ++ traces}
        end)
        |> Enum.sort_by(fn goal -> {-goal.utility, to_string(goal.name)} end)

      choose_with_hysteresis(adjusted, current_name, held, cfg, ctx)
    end
  end

  defp choose_with_hysteresis([], _current, _held, _cfg, _ctx), do: []

  defp choose_with_hysteresis([challenger | _] = goals, current_name, held, cfg, ctx) do
    current = Enum.find(goals, &(&1.name == current_name))
    critical = Enum.find(goals, &critical_override?(&1, ctx))

    cond do
      not is_nil(critical) and (is_nil(current) or current.name != critical.name) ->
        promote(goals, critical, "критическая цель прерывает текущее намерение")

      is_nil(current) or current.name == challenger.name ->
        goals

      critical_override?(challenger, ctx) ->
        promote(goals, challenger, "критическая цель прерывает текущее намерение")

      held < cfg["min_hold_decisions"] ->
        promote(goals, current, "удержание намерения: #{held}/#{cfg["min_hold_decisions"]} решений")

      challenger.utility - current.utility < cfg["switch_margin"] ->
        promote(goals, current, "гистерезис: преимущество соперника меньше #{fmt(cfg["switch_margin"])}")

      true ->
        promote(goals, challenger, "смена намерения: преимущество прошло порог #{fmt(cfg["switch_margin"])}")
    end
  end

  defp promote(goals, selected, trace) do
    selected = %{selected | brain_reasons: (selected.brain_reasons || []) ++ [trace]}
    [selected | Enum.reject(goals, &(&1.name == selected.name))]
  end

  defp critical_override?(%{name: :fight}, ctx), do: not is_nil(ctx.combat_state)

  defp critical_override?(%{name: name}, ctx) when name in [:heal, :rest] do
    urgent = get_in(ctx.configs || %{}, ["needs_urgent"]) || %{}
    hp_ratio = ctx.hero.hp / max(1, ctx.hero.max_hp)
    hp_ratio < numeric(urgent["hp_ratio"], 0.5) or
      ctx.needs.fatigue > numeric(urgent["fatigue"], 75)
  end

  defp critical_override?(_goal, _ctx), do: false

  defp current_intent(state_data), do: get_in(state_data, ["brain", "intent"]) || %{}

  defp recent_goals(state_data, window) do
    state_data
    |> get_in(["brain", "decision_log"])
    |> case do
      log when is_list(log) -> log |> Enum.take(-max(0, integer(window, 0))) |> Enum.map(& &1["goal"])
      _ -> []
    end
  end

  defp stable_jitter(_ctx, _goal, novelty) when novelty <= 0, do: 0.0

  defp stable_jitter(ctx, goal, novelty) do
    hero_key = ctx.hero.id || ctx.hero.name || "hero"
    bucket = "#{hero_key}|#{ctx.hero.game_day}|#{trunc(ctx.hour)}|#{goal}"
    <<number::unsigned-32, _::binary>> = :crypto.hash(:sha256, bucket)
    ((number / 4_294_967_295) * 2.0 - 1.0) * novelty
  end

  defp intent_cfg(configs) do
    brain = configs["brain"] || %{}
    supplied = brain["intent"] || %{}
    Map.merge(@intent_defaults, supplied)
  end

  defp outcome_kind(result) when result in [:error, :failure, :failed], do: :failure
  defp outcome_kind(result) when result in [:ok, :success, :progress], do: :progress
  defp outcome_kind(%{progress: true}), do: :progress
  defp outcome_kind(%{"progress" => true}), do: :progress
  defp outcome_kind(%{success: false}), do: :failure
  defp outcome_kind(%{"success" => false}), do: :failure
  defp outcome_kind(_), do: :unknown

  defp parse_goal(goal) when is_binary(goal) do
    try do
      String.to_existing_atom(goal)
    rescue
      ArgumentError -> nil
    end
  end

  defp parse_goal(goal) when is_atom(goal), do: goal
  defp parse_goal(_), do: nil

  defp add_trace(traces, true, trace), do: traces ++ [trace]
  defp add_trace(traces, false, _trace), do: traces
  defp numeric(value, _fallback) when is_number(value), do: value * 1.0
  defp numeric(_value, fallback), do: fallback * 1.0
  defp integer(value, _fallback) when is_integer(value), do: value
  defp integer(_value, fallback), do: fallback
  defp signed(value) when value >= 0, do: "+#{fmt(value)}"
  defp signed(value), do: fmt(value)

  # --- Стадия 2: причуды/связи (прозрачно проксируем Graph.enrich) ----------

  defp enrich_stage(goals, ctx), do: TesIdle.Game.Brain.Graph.enrich(goals, ctx)

  # --- Стадия 3: мир → решения ----------------------------------------------

  defp world_stage(goals, ctx) do
    terms = world_terms(ctx)
    cap = world_cap(ctx)

    Enum.map(goals, fn goal ->
      mods = terms[goal.name] || []

      case mods do
        [] ->
          goal

        mods ->
          delta = mods |> Enum.reduce(0.0, fn {d, _}, s -> s + d end) |> clamp(cap)

          if delta == 0.0 do
            goal
          else
            reasons = Enum.map(mods, fn {_d, r} -> "#{r} (#{fmt(delta)})" end)

            %{goal |
              utility: (goal.utility + delta) |> max(0.0) |> min(1.0),
              reason: "#{goal.reason} · мир",
              brain_reasons: (goal.brain_reasons || []) ++ reasons}
          end
      end
    end)
  end

  @doc """
  Мир → модификаторы целей по характеру. Возвращает %{goal => [{delta, reason}]}.

  Правила (характер решает, событие лишь повод):
    - дракон: осторожные (caution>60) прячутся (travel/explore −), храбрые (bravery>65) ищут боя (+fight)
    - волна монстров рядом: храбрые (+fight), осторожные не лезут (−explore)
    - война в регионе героя: осторожные не путешествуют (−travel), жадные режут шопинг (цены ×1.4)
    - ярмарка в городе: +shop (цены −20%), +socialize (гулянье)
    - затмение: +steal (тени длиннее), +break_in (темнота скрывает)
    - гроза/ливень: осторожные не идут в путь (−travel), дома уютнее (+rest)
  """
  def world_terms(ctx) do
    world = if is_map(ctx.world), do: ctx.world, else: %{}
    events = world["events"] || []
    wars = world["wars"] || []

    p = ctx.personality
    caution = Personality.trait(p, :caution)
    bravery = Personality.trait(p, :bravery)
    greed = Personality.trait(p, :greed)
    loc_id = ctx.location && to_string(ctx.location.id)

    dragon? = Enum.any?(events, &(&1["type"] == "dragon"))
    eclipse? = Enum.any?(events, &(&1["type"] == "eclipse"))
    wave_here? = Enum.any?(events, &(&1["type"] == "monster_wave" and event_here?(&1, loc_id)))
    fair_here? = Enum.any?(events, &(&1["type"] == "fair" and event_here?(&1, loc_id)))
    war_here? = region_at_war?(ctx, wars)

    rules =
      [
        if(dragon?, do: dragon_rules(caution, bravery), else: %{}),
        if(wave_here?, do: wave_rules(bravery, caution), else: %{}),
        if(war_here?, do: war_rules(caution, greed, bravery), else: %{}),
        if(fair_here?, do: fair_rules(), else: %{}),
        if(eclipse?, do: eclipse_rules(), else: %{}),
        weather_rules(ctx.weather, caution),
      ]

    Enum.reduce(rules, %{}, &merge_mods/2)
  end

  defp dragon_rules(caution, bravery) do
    %{}
    |> put_if(caution > 60, :travel, -0.12, "дракон в небе: осторожный пережидает")
    |> put_if(caution > 60, :explore, -0.08, "дракон в небе: осторожный пережидает")
    |> put_if(bravery > 65, :fight, 0.10, "дракон в небе: храбрый ищет боя")
  end

  defp wave_rules(bravery, caution) do
    %{}
    |> put_if(bravery > 55, :fight, 0.08, "волна монстров: храбрый встаёт стеной")
    |> put_if(caution > 60, :explore, -0.06, "волна монстров: осторожный не лезет")
  end

  defp war_rules(caution, greed, bravery) do
    %{}
    |> put_if(caution > 55, :travel, -0.10, "в регионе война: осторожный не путешествует")
    |> put_if(greed > 55, :shop, -0.05, "война взвинтила цены: жадный ждёт")
    |> put_if(bravery > 65, :fight, 0.05, "в регионе война: храброму сам Бог велел")
  end

  defp fair_rules do
    %{shop: [{0.10, "ярмарка: торговцы сбавили цены"}], socialize: [{0.08, "ярмарка: гулянье и слухи"}]}
  end

  defp eclipse_rules do
    %{steal: [{0.10, "затмение: тени длиннее, глаза короче"}], break_in: [{0.05, "затмение: темнота скрывает"}]}
  end

  defp weather_rules("storm", caution) do
    %{}
    |> put_if(caution > 55, :travel, -0.10, "гроза: осторожный не идёт в путь")
    |> put_if(true, :rest, 0.05, "гроза: дома уютнее")
  end

  defp weather_rules("rain", caution), do: put_if(%{}, caution > 55, :travel, -0.06, "ливень: осторожный пережидает")
  defp weather_rules(_, _), do: %{}

  # --- Хелперы ---------------------------------------------------------------

  defp event_here?(event, loc_id) do
    event_loc = event["location_id"]
    is_nil(event_loc) or event_loc == loc_id
  end

  defp region_at_war?(ctx, wars) do
    faction = Law.faction_for(ctx)

    Enum.any?(wars, fn pair ->
      case String.split(pair || "", "|") do
        [a, b] -> faction in [a, b]
        _ -> false
      end
    end)
  end

  defp put_if(terms, true, goal, delta, reason) do
    Map.update(terms, goal, [{delta, reason}], &[{delta, reason} | &1])
  end

  defp put_if(terms, false, _goal, _delta, _reason), do: terms

  defp merge_mods(new, acc) do
    Map.merge(acc, new, fn _k, a, b -> a ++ b end)
  end

  defp world_cap(ctx), do: get_in(ctx.configs || %{}, ["world_limits", "utility_cap"]) || 0.15

  defp clamp(v, cap) when is_number(v), do: v |> max(-cap) |> min(cap) |> round4()
  defp round4(v), do: round(v * 10_000) / 10_000

  defp fmt(v), do: :erlang.float_to_binary(v * 1.0, decimals: 2)
end

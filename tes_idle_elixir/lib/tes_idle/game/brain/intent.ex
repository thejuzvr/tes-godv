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

  @doc "Полная оценка целей: base → enrich → world. Отсортировано по utility."
  def evaluate(ctx) do
    ctx
    |> Goal.base_goals()
    |> enrich_stage(ctx)
    |> world_stage(ctx)
    |> Enum.sort_by(&(-&1.utility))
  end

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

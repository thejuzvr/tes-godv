defmodule TesIdle.Game.Brain.Graph do
  @moduledoc """
  Микро-мозг в Utility AI (ROADMAP Часть I, B-3).

  Обогащает оценку целей связями между чертами и причудами:

      utility_v2 = utility_v1 + Σ(связи) + причуды,  кэп ±cap (default 0.15)

  Каждое обогащение возвращает reason-trace — «почему мозг склонился».
  Одинаковые нужды + разные мозги = разные судьбы.
  """

  alias TesIdle.Game.Brain.Genome
  alias TesIdle.Game.Personality

  @doc "Включён ли мозг (config game_configs[\"brain\"][\"enabled\"])."
  def enabled?(ctx) do
    get_cfg(ctx)["enabled"] == true
  end

  @doc """
  Обогащает список целей. Цели с utility <= 0 не воскресает.
  Возвращает цели с обновлёнными utility/reason и заполненным brain_reasons.
  """
  def enrich(goals, ctx) do
    if enabled?(ctx) do
      cfg = get_cfg(ctx)
      cap = cfg["cap"] || 0.15
      hero = ctx.hero

      {links, _} = current_links(hero)
      quirks = hero_quirks(hero)

      Enum.map(goals, fn goal ->
        {link_mod, link_reasons} = link_term(goal.name, links, ctx, cfg)
        {quirk_mod, quirk_reasons} = quirk_term(goal.name, quirks, ctx)
        modifier = clamp(link_mod + quirk_mod, cap)

        if modifier == 0.0 do
          goal
        else
          new_utility = goal.utility |> Kernel.+(modifier) |> max(0.0) |> min(1.0)
          reasons = Enum.map(link_reasons ++ quirk_reasons, &("#{&1} (#{fmt(modifier)})"))

          %{goal |
            utility: new_utility,
            reason: "#{goal.reason} · мозг",
            brain_reasons: reasons}
        end
      end)
    else
      goals
    end
  end

  @doc "Лог решения и metadata intent в state_data[\"brain\"] (чисто, без Repo)."
  def log_decision(state_data, goal, ctx) do
    state_data = if is_map(state_data), do: state_data, else: %{}
    brain = state_data["brain"] || %{}
    log = brain["decision_log"] || []
    previous = brain["intent"] || %{}
    goal_name = to_string(goal.name)
    switched = is_binary(previous["goal"]) and previous["goal"] != goal_name
    held = if previous["goal"] == goal_name, do: integer(previous["held_decisions"], 0) + 1, else: 1

    entry = %{
      "day" => ctx.hero.game_day,
      "hour" => round(ctx.hour * 10) / 10,
      "goal" => goal_name,
      "utility" => round(goal.utility * 1000) / 1000,
      "reasons" => goal.brain_reasons || [],
      "world" => world_snapshot(ctx),
    }

    intent =
      previous
      |> Map.put("goal", goal_name)
      |> Map.put("held_decisions", held)
      |> Map.put("switched", switched)
      |> Map.put("previous_goal", if(switched, do: previous["goal"], else: previous["previous_goal"]))
      |> Map.put("selected_day", ctx.hero.game_day)
      |> Map.put("selected_hour", round(ctx.hour * 10) / 10)
      |> Map.put("utility", entry["utility"])
      |> Map.put_new("frustration", 0.0)

    brain
    |> Map.put("intent", intent)
    |> Map.put("decision_log", Enum.take(log ++ [entry], -50))
    |> then(&Map.put(state_data, "brain", &1))
  end

  defp integer(value, _fallback) when is_integer(value), do: value
  defp integer(_value, fallback), do: fallback

  defp world_snapshot(ctx) do
    world = if is_map(ctx.world), do: ctx.world, else: %{}

    %{
      "weather" => ctx.weather,
      "events" => Enum.map(world["events"] || [], &(&1["type"])),
      "wars" => length(world["wars"] || []),
    }
  end

  # --- Связи -------------------------------------------------------------

  # Текущие связи героя: дрейф из state_data, иначе базовые из генома.
  # Возвращает {links по строковым ключам "a~b", базовые веса}
  def current_links(hero) do
    genome_links =
      if hero.brain_hash do
        hero.brain_hash |> Genome.derive() |> Map.get(:links) |> to_string_keys()
      else
        %{}
      end

    drifted = read_brain_state(hero)["links"] || %{}
    links = Map.merge(genome_links, drifted)
    {links, genome_links}
  end

  defp link_term(_goal, links, _ctx, _cfg) when map_size(links) == 0, do: {0.0, []}

  # C-2 (аудит поведения 2026-09): связи взвешиваются ПО ЦЕЛИ.
  # Пары генома имеют семантику — используем её: каждая связь поддерживает
  # конкретные цели. Связи вне маппинга для данной цели не учитываются,
  # поэтому разные мозги по-разному склоняются к разным целям.
  # (Раньше считался один агрегат по всем 15 связям — константа для всех целей.)
  @link_goals %{
    {"bravery", "greed"} => [:fight, :loot, :steal],
    {"bravery", "caution"} => [:fight, :travel],
    {"curiosity", "caution"} => [:explore, :break_in],
    {"curiosity", "patience"} => [:explore, :gather],
    {"greed", "dexterity"} => [:steal, :break_in],
    {"greed", "patience"} => [:fish, :gather, :loot],
    {"sociability", "empathy"} => [:socialize, :pet_care],
    {"sociability", "bravery"} => [:socialize, :fight],
    {"tenacity", "patience"} => [:gather, :fish, :complete_quest],
    {"caution", "dexterity"} => [:break_in, :steal],
    {"empathy", "patience"} => [:pet_care, :fish],
    {"bravery", "curiosity"} => [:explore, :travel],
    {"greed", "sociability"} => [:shop, :socialize],
    {"tenacity", "bravery"} => [:fight, :complete_quest],
    {"empathy", "caution"} => [:pet_care, :heal],
  }

  defp link_term(goal_name, links, ctx, cfg) do
    gain = cfg["link_gain"] || 0.35
    p = ctx.personality
    goal_str = to_string(goal_name)

    {total, contributions} =
      Enum.reduce(links, {0.0, []}, fn {key, w}, {acc, cs} ->
        [a, b] = String.split(key, "~")
        supported = Map.get(@link_goals, {a, b}) || Map.get(@link_goals, {b, a}) || []

        if goal_name in supported do
          ta = Personality.trait(p, String.to_existing_atom(a)) / 100
          tb = Personality.trait(p, String.to_existing_atom(b)) / 100
          contribution = w * ta * tb
          reason = "#{a}×#{b}: #{fmt(ta)}×#{fmt(tb)}×#{fmt(w)} → #{fmt(contribution)}"
          {acc + contribution, [{contribution, reason} | cs]}
        else
          {acc, cs}
        end
      end)

    # Нормируем на число связей, поддерживающих эту цель (а не на все 15) —
    # иначе цели с 1-2 связями систематически слабее целей с 5.
    supported_count =
      Enum.count(links, fn {key, _} ->
        [a, b] = String.split(key, "~")
        goal_name in (Map.get(@link_goals, {a, b}) || Map.get(@link_goals, {b, a}) || [])
      end)

    n = max(1, supported_count)
    modifier = total / n * gain

    top =
      contributions
      |> Enum.sort_by(fn {c, _} -> -abs(c) end)
      |> Enum.take(2)
      |> Enum.map(&elem(&1, 1))

    {modifier, top ++ ["цель: #{goal_str}"]}
  end

  # --- Причуды ------------------------------------------------------------

  defp quirk_term(goal_name, quirks, ctx) do
    # C-1 (аудит поведения 2026-09): погода — из ядра мира (ctx.weather, ключи
    # clear/cloud/rain/storm/snow), а не легаси location.weather (заморожен в БД,
    # сравнение с русскими названиями никогда не срабатывало).
    weather = ctx.weather
    flags = if ctx.location && ctx.location.flags, do: ctx.location.flags, else: %{}
    recent_victory = Enum.any?(ctx.memories || [], &(&1["type"] == "victory"))

    mods =
      case goal_name do
        :explore ->
          if :superstitious in quirks and weather in ["storm", "snow", "fog"],
            do: [{-0.06, "суеверен: непогода пугает"}], else: []

        :travel ->
          cond do
            :afraid_of_water in quirks and flags["water"] == true -> [{-0.05, "боится воды"}]
            :afraid_of_water in quirks and weather in ["rain", "storm"] -> [{-0.03, "боится воды: осадки"}]
            true -> []
          end

        :socialize ->
          if :braggart in quirks and recent_victory, do: [{0.05, "хвастун: есть чем похвастать"}], else: []

        :loot ->
          if :cup_collector in quirks, do: [{0.04, "коллекционирует: ищет безделушки"}], else: []

        :shop ->
          if :sweet_tooth in quirks, do: [{0.03, "сладкоежка: заглянет к торговцу"}], else: []

        :fight ->
          if :spider_panic in quirks and ctx.location_type == "dungeon",
            do: [{-0.04, "панически боится пауков: в подземелье неспокойно"}], else: []

        :fish ->
          cond do
            :dawn_fisher in quirks and ctx.hour >= 5 and ctx.hour <= 8 -> [{0.06, "рыбак на рассвете: утренний клёв"}]
            :afraid_of_water in quirks -> [{-0.08, "боится воды: к самой воде не подходит"}]
            true -> []
          end

        :steal ->
          cond do
            :night_thief in quirks and (ctx.hour >= 22 or ctx.hour < 6) -> [{0.07, "ночной вор: тьма — союзница"}]
            :night_thief in quirks and ctx.hour >= 8 and ctx.hour <= 18 -> [{-0.04, "ночной вор: днём неловко"}]
            true -> []
          end

        _ -> []
      end

    total = Enum.reduce(mods, 0.0, fn {m, _}, acc -> acc + m end)
    reasons = Enum.map(mods, &elem(&1, 1))
    {total, reasons}
  end

  # --- Хелперы ------------------------------------------------------------

  def hero_quirks(hero) do
    if hero.brain_hash do
      hero.brain_hash |> Genome.derive() |> Map.get(:quirks)
    else
      []
    end
  end

  def read_brain_state(hero) do
    case Jason.decode(hero.state_data || "{}") do
      {:ok, %{"brain" => brain}} when is_map(brain) -> brain
      _ -> %{}
    end
  end

  def to_string_keys(tuple_links) do
    Map.new(tuple_links, fn {{a, b}, w} -> {"#{a}~#{b}", w} end)
  end

  defp get_cfg(ctx), do: (ctx.configs || %{})["brain"] || %{}

  defp clamp(v, cap) when is_number(v), do: v |> max(-cap) |> min(cap) |> round4()
  defp round4(v), do: round(v * 10_000) / 10_000

  defp fmt(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp fmt(v) when is_integer(v), do: Integer.to_string(v)
end

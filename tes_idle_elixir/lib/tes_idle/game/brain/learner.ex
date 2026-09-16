defmodule TesIdle.Game.Brain.Learner do
  @moduledoc """
  Обучение микро-мозга (ROADMAP Часть I, B-4).

  Три механизма жизни мозга:

  1. **Пластичность черт** — события сдвигают черты; бюджет 10 п./игровую
     неделю (config `brain.plasticity_week`); возврат к гено-базе.
  2. **Дрейф связей** — успех усиливает связь (+drift_up), провал ослабляет
     (-drift_down); коридор ±drift_range от гено-базы.
  3. **Перерождение** — смерть не конец: generation+1, черты наследуются
     с мутацией ±rebirth_mutation, связи переигрываются, причуды постоянны.

  Хранение: черты в `heroes.personality`, связи/бюджет/лог/поколение в
  `state_data["brain"]` (JSONB).
  """

  alias TesIdle.Game.Brain.{Genome, Graph}
  alias TesIdle.Game.Personality

  # События тика → дельты черт и затрагиваемые связи
  @outcome_events %{
    victory:   %{"deltas" => %{:bravery => 0.4, :tenacity => 0.2, :caution => -0.1},
                "drift_traits" => ["bravery", "tenacity", "caution"], "outcome" => :up},
    defeat:    %{"deltas" => %{:caution => 0.6, :bravery => -0.3},
                "drift_traits" => ["caution", "bravery"], "outcome" => :down},
    social:    %{"deltas" => %{:sociability => 0.25, :empathy => 0.15},
                "drift_traits" => ["sociability", "empathy"], "outcome" => :up},
    rest:      %{"deltas" => %{:patience => 0.1},
                "drift_traits" => ["patience"], "outcome" => :up},
    earn:      %{"deltas" => %{:greed => 0.2},
                "drift_traits" => ["greed", "patience"], "outcome" => :up},
    explore:   %{"deltas" => %{:curiosity => 0.15},
                "drift_traits" => ["curiosity", "patience"], "outcome" => :up},
  }

  # --- Обучение за тик ------------------------------------------------------

  @doc "Возвращает {personality (атомные ключи) | nil, brain_state | nil}. nil = мозг выключен."
  def learn(hero, result, configs) do
    cfg = (configs || %{})["brain"] || %{}

    if cfg["enabled"] == true do
      p = Personality.normalize(hero.personality)
      brain = Graph.read_brain_state(hero)
      {links, base_links} = Graph.current_links(hero)
      budget = brain["budget"] || %{"week" => week_of(hero.game_day), "spent" => 0.0}

      outcome_keys = outcomes(result)
      events = Enum.map(outcome_keys, &Map.get(@outcome_events, &1)) |> Enum.reject(&is_nil/1)

      # 1. Пластичность черт с недельным бюджетом
      {p2, budget2} = apply_deltas(p, events, budget, cfg, hero)

      # 2. Возврат к гено-базе — гомеостаз личности.
      # C-3 (аудит поведения 2026-09): раньше 0.02/тик (~0.5/черта/нед) съедал
      # весь недельный бюджет пластичности (10 п. на все черты) — личность
      # застывала у гено-базы. Теперь возврат раз в игровой день.
      {p3, returned?} = maybe_return_to_base(p2, hero, cfg)

      # 3. Дрейф связей по успеху/провалу
      links2 = drift_links(links, base_links, events, cfg)

      brain2 =
        brain
        |> Map.put("links", links2)
        |> Map.put("budget", budget2)
        |> then(fn b -> if returned?, do: Map.put(b, "last_return_day", hero.game_day), else: b end)

      {p3, brain2}
    else
      {nil, nil}
    end
  end

  # --- Перерождение ---------------------------------------------------------

  @doc "Смерть → перерождение: {personality, brain_state}."
  def reborn(hero, configs) do
    cfg = (configs || %{})["brain"] || %{}
    mutation = cfg["rebirth_mutation"] || 5
    brain = Graph.read_brain_state(hero)
    generation = (brain["generation"] || 1) + 1

    {traits, links} =
      if hero.brain_hash do
        genome = Genome.derive(hero.brain_hash)
        traits = Map.new(genome.traits, fn {t, v} -> {t, clamp100(v + rand_int(-mutation, mutation))} end)

        links =
          genome.links
          |> Graph.to_string_keys()
          |> Map.new(fn {k, w} -> {k, clamp(w + rand_small(), -1.0, 1.0)} end)

        {traits, links}
      else
        # Легаси-герой без hash: черты сохраняются, лёгкая мутация
        traits =
          Personality.normalize(hero.personality)
          |> Map.new(fn {t, v} -> {t, clamp100(v + rand_int(-mutation, mutation))} end)

        {traits, brain["links"] || %{}}
      end

    log = brain["decision_log"] || []

    new_brain =
      brain
      |> Map.put("generation", generation)
      |> Map.put("links", links)
      |> Map.put("budget", %{"week" => week_of(hero.game_day), "spent" => 0.0})
      |> Map.put("decision_log", log ++ [%{
        "day" => hero.game_day,
        "hour" => nil,
        "goal" => "__rebirth__",
        "utility" => nil,
        "reasons" => ["Перерождение: поколение #{generation}"],
      }])

    {traits, new_brain}
  end

  # --- Служебное ------------------------------------------------------------

  defp outcomes(result) do
    combat = result[:combat_result]

    cond do
      combat && combat[:victory] -> [:victory]
      combat -> [:defeat]
      result[:state_to] == "socializing" -> [:social]
      result[:state_to] == "resting" -> [:rest]
      (result[:gold_change] || 0) > 0 -> [:earn]
      result[:state_to] == "exploring" -> [:explore]
      true -> []
    end
  end

  defp apply_deltas(p, events, budget, cfg, hero) do
    week = week_of(hero.game_day)
    week_budget = cfg["plasticity_week"] || 10.0

    budget =
      if budget["week"] == week, do: budget, else: %{"week" => week, "spent" => 0.0}

    wanted =
      Enum.reduce(events, %{}, fn ev, acc ->
        Enum.reduce(ev["deltas"], acc, fn {trait, d}, a ->
          Map.update(a, trait, d, &(&1 + d))
        end)
      end)

    remaining = max(0.0, week_budget - budget["spent"])
    total_wanted = wanted |> Map.values() |> Enum.map(&abs/1) |> Enum.sum()

    {p2, applied} =
      if total_wanted <= remaining and total_wanted > 0 do
        p2 = Enum.reduce(wanted, p, fn {t, d}, acc -> shift(acc, t, d) end)
        {p2, total_wanted}
      else
        scale = if total_wanted > 0, do: remaining / total_wanted, else: 0.0
        p2 = Enum.reduce(wanted, p, fn {t, d}, acc -> shift(acc, t, d * scale) end)
        {p2, remaining}
      end

    {p2, Map.put(budget, "spent", round2(budget["spent"] + applied))}
  end

  # Возврат к гено-базе: раз в игровой день (state_data["brain"]["last_return_day"]),
  # чтобы гомеостаз не съедал недельный бюджет пластичности.
  defp maybe_return_to_base(p, hero, cfg) do
    last_day = Graph.read_brain_state(hero)["last_return_day"]

    if last_day == nil or hero.game_day > last_day do
      {return_to_base(p, hero, cfg), true}
    else
      {p, false}
    end
  end

  defp return_to_base(p, hero, cfg) do
    base_return = cfg["base_return"] || 0.002

    if hero.brain_hash do
      base = Genome.base_traits(hero.brain_hash)

      Enum.reduce(p, %{}, fn {t, v}, acc ->
        target = Map.get(base, t, v)
        step = if v < target, do: min(base_return, target - v), else: -min(base_return, v - target)
        Map.put(acc, t, clamp100(v + step))
      end)
    else
      p
    end
  end

  defp drift_links(links, base_links, events, cfg) do
    up = cfg["drift_up"] || 0.01
    down = cfg["drift_down"] || 0.015
    range = cfg["drift_range"] || 0.3

    touched =
      events
      |> Enum.flat_map(& &1["drift_traits"])
      |> Enum.uniq()

    outcome =
      events
      |> Enum.map(& &1["outcome"])
      |> Enum.find(:up, &(&1 == :down))

    delta = if outcome == :down, do: -down, else: up

    Map.new(links, fn {key, w} ->
      [a, b] = String.split(key, "~")

      if a in touched or b in touched do
        base_w = Map.get(base_links, key, w)
        limit_lo = base_w - range
        limit_hi = base_w + range
        {key, w |> Kernel.+(delta) |> clamp(limit_lo, limit_hi) |> round2()}
      else
        {key, w}
      end
    end)
  end

  defp shift(p, trait, delta), do: Map.update!(p, trait, &clamp100(&1 + delta))

  defp week_of(day), do: div(day - 1, 7) + 1

  defp clamp100(v), do: v |> max(0) |> min(100) |> round2()
  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
  defp round2(v), do: round(v * 100) / 100

  defp rand_int(lo, hi), do: Enum.random(lo..hi)
  defp rand_small, do: (Enum.random(-50..50) / 1000) * 10 |> Kernel.*(0.1) |> Float.round(3)
end

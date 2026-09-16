defmodule TesIdle.Game.Narrative.Composer do
  @moduledoc """
  N-2/N-3: сборка «средних нарративов» — сцена вокруг костяка-шаблона.

      Scene = [Opener] + backbone + [Closer]
        Opener: пул openers_<weather> (clear/cloud/rain/storm/snow) — самодостаточное
                предложение о погоде из мира (ctx.weather, fallback "clear").
        Closer: иерархия источников (только один на сцену):
          1. quirk_<name>     — персонажная реакция по причуде BrainHash (0..2 у героя);
          2. memory_<type>    — реакция на свежую память (victory/defeat/discovery/
                                social/shop/travel, давность ≤ memory_days дней);
          3. closers_<band>   — fallback по настроению (high ≥60, mid, low ≤40),
                                {hero_name} подставляется TemplateEngine.render_vars/2.

  Управление — game_configs["composer"]:
      %{"enabled" => true,
        "types" => ["explore", "rest", "travel", ...],          # полные сцены
        "closer_only_types" => ["combat_result", ...],           # только closer, без опенера
        "opener_chance" => 0.8, "closer_chance" => 0.6,
        "quirk_chance" => 0.5, "memory_chance" => 0.4, "memory_days" => 2}
  Пустой конфиг или enabled=false → костяк возвращается без изменений
  (безопасный дефолт: пока конфиг не заведён, поведение прежнее).
  """

  alias TesIdle.Game.Narrative.{FragmentPool, TemplateEngine}

  def compose(template_type, backbone, ctx, vars, opts \\ []) do
    cfg = cfg(ctx)

    if enabled?(cfg, template_type) and not Keyword.get(opts, :full_scene, false) do
      opener = if closer_only?(cfg, template_type), do: nil, else: draw_opener(cfg, ctx, vars)

      [opener, backbone, draw_closer(cfg, ctx, vars)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")
    else
      backbone
    end
  end

  # --- Private ---

  defp cfg(%{configs: configs}) when is_map(configs), do: Map.get(configs, "composer") || %{}
  defp cfg(_), do: %{}

  defp enabled?(cfg, template_type) do
    Map.get(cfg, "enabled", false) == true and
      (template_type in Map.get(cfg, "types", []) or closer_only?(cfg, template_type))
  end

  defp closer_only?(cfg, template_type),
    do: template_type in Map.get(cfg, "closer_only_types", [])

  # N-5: опенер тоже проходит рендер (страховка от {var} в данных пула) —
  # фрагмент с непокрытыми переменными отбрасывается, сцена без опенера.
  defp draw_opener(cfg, ctx, vars) do
    if roll(cfg, "opener_chance") do
      weather = weather_key(ctx)
      if weather, do: FragmentPool.draw("openers_" <> weather) |> render_ok(vars), else: nil
    end
  end

  # Иерархия closer: причуда → свежая память → настроение. Ровно один на сцену.
  # Рендер входит в выбор: фрагмент с непокрытыми {var} отбрасывается сразу,
  # и иерархия идёт дальше (никогда не возвращает текст с дырками).
  defp draw_closer(cfg, ctx, vars) do
    if roll(cfg, "closer_chance") do
      mem = fresh_memory(cfg, ctx, day(ctx))
      # Конкретика памяти ({monster}, {item}, {npc}) доступна closer-текстам
      all_vars = Map.merge(vars, memory_vars(mem))

      quirk_closer(cfg, ctx, all_vars) ||
        memory_closer(cfg, mem, all_vars) ||
        mood_closer(cfg, ctx, all_vars)
    end
  end

  defp render_ok(nil, _vars), do: nil

  defp render_ok(text, vars) do
    rendered = TemplateEngine.render_vars(text, vars)
    if Regex.match?(~r/\{\w+\}/, rendered), do: nil, else: rendered
  end

  defp memory_vars(nil), do: %{}

  defp memory_vars(mem) when is_map(mem) do
    %{"monster" => mem["monster"], "item" => mem["item"], "npc" => mem["npc"]}
    |> Enum.filter(fn {_k, v} -> is_binary(v) and v != "" end)
    |> Map.new()
  end

  defp memory_vars(_), do: %{}

  defp quirk_closer(cfg, ctx, all_vars) do
    if roll(cfg, "quirk_chance") do
      ctx
      |> quirks()
      |> Enum.map(&FragmentPool.draw("quirk_" <> Atom.to_string(&1)))
      |> Enum.find(&(&1 != nil))
      |> render_ok(all_vars)
    end
  end

  defp memory_closer(cfg, mem, all_vars) do
    if roll(cfg, "memory_chance") and is_map(mem) do
      case mem do
        %{"type" => type} when is_binary(type) ->
          type
          |> then(&FragmentPool.draw("memory_" <> &1))
          |> render_ok(all_vars)

        _ ->
          nil
      end
    end
  end

  defp mood_closer(_cfg, ctx, all_vars) do
    ctx
    |> mood()
    |> mood_band()
    |> then(&FragmentPool.draw("closers_" <> &1))
    |> render_ok(all_vars)
  end

  defp fresh_memory(cfg, ctx, current_day) when is_number(current_day) do
    window = Map.get(cfg, "memory_days", 2)
    ctx
    |> memories()
    |> Enum.filter(fn m -> is_map(m) and is_integer(m["day"]) and current_day - m["day"] <= window end)
    |> List.last()
  end

  defp fresh_memory(_, _, _), do: nil

  defp roll(cfg, key) do
    chance = Map.get(cfg, key)
    is_number(chance) and :rand.uniform() < chance
  end

  defp weather_key(%{weather: w}) when is_binary(w) and w != "", do: w
  defp weather_key(_), do: nil

  defp quirks(%{quirks: q}) when is_list(q), do: q
  defp quirks(_), do: []

  defp memories(%{memories: m}) when is_list(m), do: m
  defp memories(_), do: []

  defp day(%{hero: %{game_day: d}}) when is_integer(d), do: d
  defp day(_), do: nil

  defp mood(%{mood: m}) when is_number(m), do: m
  defp mood(_), do: 50.0

  defp mood_band(mood) when mood >= 60.0, do: "high"
  defp mood_band(mood) when mood <= 40.0, do: "low"
  defp mood_band(_), do: "mid"
end

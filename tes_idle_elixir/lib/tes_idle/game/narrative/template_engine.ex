defmodule TesIdle.Game.Narrative.TemplateEngine do
  @moduledoc """
  Selects and formats narrative templates from DB.
  Uses safe regex replacement to avoid crashes on missing variables.
  Описательные пулы (terrain, npc_name, fish_name, ...) берутся из БД —
  Narrative.FragmentPool (N-1, таблица narrative_fragments).
  """

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeTemplate
  alias TesIdle.Game.Narrative.{Composer, FragmentPool}
  import Ecto.Query

  @max_dedup 10

  # Map state_to values to DB template_type values
  @state_to_template %{
    "exploring" => "explore",
    "fighting" => "combat_start",
    "resting" => "rest",
    "shopping" => "shop",
    "socializing" => "social",
    "traveling" => "travel",
    "looting" => "loot",
    "dead" => "death",
    "fishing" => "fishing",
    "gathering" => "gather",
    "sneaking" => "steal",
    "breaking_in" => "break_in",
    "jailed" => "jail",
    "pet_care" => "pet_care",
  }

  def generate(result, ctx) do
    template_type = cond do
      result[:combat_result] ->
        if result[:hero_defeated], do: "combat_defeat", else: "combat_result"
      result[:combat_start] -> "combat_start"
      result[:state_to] == "dead" -> "death"
      true ->
        state = result.state_to || "system"
        Map.get(@state_to_template, state, state)
    end

    templates = load_templates(template_type, ctx)
    chosen = choose_template(templates, ctx.hero) || %{text: "Продолжает свой путь.", source: "system"}
    context = build_context(result, ctx, template_type)
    text = safe_format(chosen.text, context)
    # N-2: сцена = [опенер погоды] + костяк + [closer по настроению]
    # N-4: llm-сцена — полный текст, Composer её не размножает.
    text = Composer.compose(template_type, text, ctx, context, full_scene: chosen.source == "llm")

    %{type: template_type, text: text}
  end

  @doc "Подстановка {var}-переменных (публично — использует Composer для closer-фрагментов)."
  def render_vars(template, vars), do: safe_format(template, vars)

  defp load_templates(type, ctx) do
    query = from t in NarrativeTemplate,
      where: t.template_type == ^type and t.is_active == true,
      select: %{text: t.text_template, source: t.source}

    query = if ctx.location do
      from t in query,
        where: is_nil(t.location_id) or t.location_id == ^ctx.location.id
    else
      from t in query, where: is_nil(t.location_id)
    end

    Repo.all(query)
  end

  defp choose_template([], _hero), do: nil
  defp choose_template(templates, hero) do
    used = get_used_templates(hero)
    available = Enum.reject(templates, &(&1.text in used))

    chosen = case available do
      [] -> Enum.random(templates)
      _ -> Enum.random(available)
    end

    track_used(hero, chosen.text)
    chosen
  end

  defp get_used_templates(hero) do
    case Jason.decode(hero.state_data || "{}") do
      {:ok, %{"used_templates" => used}} when is_list(used) -> used
      _ -> []
    end
  end

  defp track_used(hero, template) do
    # Читаем СВЕЖЕЕ state_data из БД: к этому моменту pipeline уже сохранил
    # brain/plan/memories — запись по устаревшему снимку затирает их (гонка писателей).
    fresh = Repo.reload!(hero)
    used = get_used_templates(fresh)
    new_used = (used ++ [template]) |> Enum.take(-@max_dedup)

    state_data = case Jason.decode(fresh.state_data || "{}") do
      {:ok, data} when is_map(data) -> Map.put(data, "used_templates", new_used)
      _ -> %{"used_templates" => new_used}
    end

    fresh
    |> Ecto.Changeset.change(%{state_data: Jason.encode!(state_data)})
    |> Repo.update!()
  end

  defp build_context(result, ctx, template_type) do
    base = %{
      "hero_name" => ctx.hero.name,
      "location_name" => if(ctx.location, do: ctx.location.name, else: ""),
      "location_type" => to_string(ctx.location_type || ""),
      "mood" => Float.round((ctx.hero.mood || 50.0), 1),
      "has_inn" => if(ctx.location, do: ctx.location.has_inn, else: false),
      "god_name" => "Талос",
    }

    # Action-specific context. Пул пуст → переменной в context нет →
    # safe_format оставит {terrain} видимым (честный сигнал незаполненного пула).
    action_ctx = case template_type do
      "explore" ->
        %{}
        |> Map.merge(draw_fragment("terrain", "terrains"))
        |> Map.merge(draw_fragment("discovery", "discoveries"))
        |> Map.merge(draw_fragment("landmark", "landmarks"))
      "combat_start" ->
        combat = result[:combat_start] || %{}
        %{
          "monster_name" => Map.get(combat, :monster_name, Map.get(combat, "monster_name", "враг")),
        }
        |> Map.merge(draw_fragment("landmark", "landmarks"))
      "combat_result" ->
        combat = result[:combat_result] || %{}
        %{
          "monster_name" => Map.get(combat, :monster_name, Map.get(combat, "monster_name", "враг")),
          "xp" => Map.get(combat, :xp, Map.get(combat, "xp", 0)),
          "gold" => Map.get(combat, :gold, Map.get(combat, "gold", 0)),
          "rounds" => Map.get(combat, :rounds, Map.get(combat, "rounds", 1)),
        }
        |> Map.merge(draw_fragment("_combat_verbs", "combat_verbs"))
      "combat_defeat" ->
        combat = result[:combat_result] || %{}
        %{
          "monster_name" => Map.get(combat, :monster_name, Map.get(combat, "monster_name", "враг")),
        }
      "shop" ->
        %{
          "item_name" => "припасы",
          "gold_spent" => Map.get(result, :gold_spent, 0),
        }
        |> Map.merge(draw_fragment("npc_name", "npc_names"))
        |> Map.merge(draw_fragment("shop_item", "shop_items"))
      "social" ->
        %{
          "gamble_result" => if(:rand.uniform() < 0.15, do: "выиграл немного золота", else: "просто поболтал"),
        }
        |> Map.merge(draw_fragment("npc_name", "npc_names"))
        |> Map.merge(draw_fragment("rumor", "rumors"))
        |> Map.merge(draw_fragment("tavern", "taverns"))
      "travel" ->
        %{
          "destination" => if(ctx.location, do: ctx.location.name, else: "неизвестное место"),
        }
      "loot" ->
        %{
          "loot_text" => "находка",
        }
      _ ->
        %{}
    end

    base
    |> Map.merge(action_ctx)
    |> Map.merge(result[:context] || %{})
    |> Map.new(fn {k, v} -> {k, to_string(v)} end)
  end

  defp safe_format(template, context) do
    Regex.replace(~r/\{(\w+)\}/, template, fn match, key ->
      Map.get(context, key, match)
    end)
  end

  @doc """
  Simple formatter: takes template_type and NarrativeContext, returns text.
  Used by NarrativeDirector after event selection.
  Falls back to legacy template types if no templates for the new event.
  """
  def format(template_type, ctx) do
    templates = load_templates(template_type, ctx)
    context = simple_context(ctx)

    {text, full_scene} = if templates == [] do
      # Fallback to legacy template type
      legacy = legacy_type(template_type)
      legacy_templates = load_templates(legacy, ctx)
      chosen = choose_template(legacy_templates, ctx.hero) || %{text: "Продолжает свой путь.", source: "system"}
      {safe_format(chosen.text, context), chosen.source == "llm"}
    else
      chosen = choose_template(templates, ctx.hero)
      # N-4/A-1b: одобренная llm-сцена — уже полный текст (опенер + костяк + closer),
      # Composer не размножает её второй сценой.
      {safe_format(chosen.text, context), chosen.source == "llm"}
    end

    # N-2: сцена вокруг костяка. Event-имя (watch_sunset, enter_city, ...)
    # смаппим к базовому типу (rest/travel/explore...) — по нему Composer
    # проверяет список types из game_configs["composer"].
    Composer.compose(legacy_type(template_type), text, ctx, context, full_scene: full_scene)
  end

  # Map Narrative Director events to legacy DB template types
  defp legacy_type(ev) do
    case ev do
      e when e in ~w(hero_victory enemy_ambush spot_bandits search_danger) -> "combat_result"
      e when e in ~w(hero_defeat) -> "combat_defeat"
      e when e in ~w(leave_city travel_road travel_shortcut cross_bridge enter_city) -> "travel"
      e when e in ~w(discover_ruin discover_cave find_shrine find_abandoned_cart notice_tracks hear_river find_tracks hear_birds smell_flowers collect_herbs) -> "explore"
      e when e in ~w(sleep_in_inn rest_by_fire) -> "rest"
      e when e in ~w(meet_merchant learn_rumors hear_song shelter_from_storm) -> "social"
      e when e in ~w(find_loot discover_treasure) -> "loot"
      e when e in ~w(hear_wolves avoid_danger) -> "combat_start"
      e when e in ~w(bad_weather) -> "travel"
      e when e in ~w(watch_sunset) -> "rest"
      e when e in ~w(remember_defeat feel_confident) -> "thought"
      e when e in ~w(generic_action) -> "explore"
      e when e in ~w(fishing_catch fishing_wait) -> "fishing"
      e when e in ~w(gather_plants) -> "gather"
      e when e in ~w(steal_clean steal_spotted) -> "steal"
      e when e in ~w(break_in_ok break_in_trap) -> "break_in"
      e when e in ~w(jail_time) -> "jail"
      e when e in ~w(pet_care_moment) -> "pet_care"
      # Полировка: shop/loot события = их template_type, но без явной строки
      # legacy-фоллбек давал "explore" (космические тексты про рвы и молнии
      # вместо рынка). Явный маппинг — страховка.
      e when e in ~w(shop loot rest social travel explore) -> e
      _ -> "explore"
    end
  end

  defp simple_context(ctx) do
    combat = ctx.combat || %{}
    travel = ctx.travel || %{}
    action = ctx.action_context || %{}

    %{
      "hero_name" => ctx.hero.name,
      "location_name" => if(ctx.location, do: ctx.location.name, else: ""),
      "location_type" => to_string(ctx.location_type || ""),
      "god_name" => "Талос",
      "mood" => Float.round(ctx.mood || 50.0, 1),
      # Не подставляем сырые enum-ы ("city", "village") в тексты —
      # описательные пулы приходят из БД (FragmentPool) ниже.
      "monster_name" => Map.get(combat, "monster_name", "враг"),
      "xp" => to_string(Map.get(combat, "monster_xp_reward", 0)),
      "gold" => to_string(Map.get(combat, "monster_gold_min", 0)),
      "rounds" => to_string(20 - Map.get(combat, "rounds_left", 20)),
      "item_name" => "припасы",
      "gold_spent" => "10",
      "loot_text" => "немного золота",
      "destination" => Map.get(travel, "destination_name", "неизвестное место"),
      "gamble_result" => "выиграл немного золота",
      # --- Фаза 2: активности (заглушки перекрываются action_context) ---
      "pet_name" => "питомец",
      "pet_species" => "зверёк",
      "pet_care_kind" => "позаботился",
      "pet_loyalty" => "70",
      "stolen_gold" => "15",
      "bounty_gold" => "25",
      "fine_gold" => "30",
      "trap_hp" => "10",
      "jail_reason" => "проступок",
      "jail_ticks" => "5",
      "jail_escaped" => "false",
      "jail_escape_fail" => "false",
      "jail_free" => "false",
      "witness_outcome" => "clean",
      "break_in_ok" => "false",
      "break_in_trap" => "false",
      "break_in_noise" => "false",
      "break_in_fail" => "false",
    }
    # --- Описательные пулы из БД (N-1) ---
    |> Map.merge(draw_fragment("terrain", "terrains"))
    |> Map.merge(draw_fragment("discovery", "discoveries"))
    |> Map.merge(draw_fragment("landmark", "landmarks"))
    |> Map.merge(draw_fragment("_combat_verbs", "combat_verbs"))
    |> Map.merge(draw_fragment("npc_name", "npc_names"))
    |> Map.merge(draw_fragment("fish_name", "fish_names"))
    |> Map.merge(draw_fragment("herb_name", "herb_names"))
    |> Map.merge(draw_fragment("witness_name", "witnesses"))
    |> Map.merge(action)
    # --- Дата-сет (CD-1): пулы живого мира. Ключ beast, НЕ monster — {monster}
    # занят конкретикой памяти в Composer (memory_vars мерджится поверх). ---
    |> Map.merge(draw_fragment("beast", "monsters"))
    |> Map.merge(draw_fragment("shop_item", "shop_items"))
    |> Map.merge(draw_fragment("rumor", "rumors"))
    |> Map.merge(draw_fragment("tavern", "taverns"))
  end

  # FragmentPool.draw/1 → %{"key" => text}; пустой пул → nil-переменной в context нет
  defp draw_fragment(key, pool) do
    case FragmentPool.draw(pool) do
      nil -> %{}
      text -> %{key => text}
    end
  end
end

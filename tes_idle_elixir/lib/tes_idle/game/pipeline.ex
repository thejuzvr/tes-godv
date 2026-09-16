defmodule TesIdle.Game.Pipeline do
  @moduledoc """
  Main game pipeline orchestrator.
  Builds context → adjusts scores → chooses action → executes → updates hero → generates narrative.
  """

  alias TesIdle.Repo
  alias TesIdle.Game.{ContextBuilder, AutoEquip, FSMExecutor}
  alias TesIdle.Game.Narrative.{TemplateEngine, NarrativeDirector, NarrativeContext}
  alias TesIdle.Schemas.{Hero, JournalEntry}
  import Ecto.Query

  @equip_check_interval 5..10

  def tick(hero_id) do
    # 1. Build context (all DB queries here)
    ctx = ContextBuilder.build(hero_id)

    # 1b. Auto-accept quest if none active.
    # Фаза 2 (аудит поведения): после завершения квеста — «окно активностей»
    # (activity_break_ticks, 3–5 тиков): герой занимается своими делами
    # (fish/gather/socialize/rest), а не мгновенно хватает новый квест.
    ctx = if ctx.active_quest == nil, do: maybe_auto_accept_quest(ctx), else: ctx

    # 2. P-2: смерть с таймером — мёртвый герой не живёт, ждёт возрождения
    cond do
      ctx.hero.state == "dead" ->
        handle_dead_tick(ctx)

      ctx.hero.hp <= 0 ->
        handle_death(ctx)

      true ->
        # 3. FSM tick (Utility AI → GOAP → Execute)
        {_fsm_state, action_module, result, new_state_data} = FSMExecutor.tick(ctx)

      if result do
        # 4. Update hero state (needs, mood, time, regen) + мозг учится на результате
        {updated_hero, brain_state} = apply_result(ctx.hero, result, ctx.configs, ctx.guild_buff)

        # 5. Auto-consume potions/food/soul stones
        updated_hero = auto_consume(updated_hero)

        # 5b-2. Quest progress tracking — возвращает true, если квест завершён
        # (Фаза 2: маркер «окна активностей» ставим в merged_sd ниже, правило 2.1)
        quest_done? = check_quest_progress(updated_hero, action_module, result)

        # 5b-1. P-3: репутация — позитивные источники (убийство монстра в регионе)
        reputation_tick(ctx, action_module, result)

        # 5b-2. Питомцы: голод/лояльность, уход, возрождение по revive_at
        pet_events = pet_tick(updated_hero, ctx.configs)

        # 5c. Memory tracking — returns updated state_data with memories
        {_updated_hero, final_state_data} = track_memories(updated_hero, action_module, result, new_state_data)

        # 5e. Prepare merged state_data for saving
        merged_sd = final_state_data |> Map.merge(result[:state_data_update] || %{})

        # Фаза 2: окно активностей после завершения квеста — маркер идёт
        # через merged_sd (единый save, правило 2.1), а не отдельный changeset.
        merged_sd = if quest_done?,
          do: Map.put(merged_sd, "activity_break_until_tick", current_tick() + activity_break_ticks()),
          else: merged_sd

        # Мозг: связи/бюджет от Learner, но decision_log берём свежий — его только что
        # дописал FSMExecutor при создании плана (Learner читал снимок до тика)
        merged_sd = if brain_state do
          fsm_brain = final_state_data["brain"] || %{}
          brain = Map.merge(brain_state, Map.take(fsm_brain, ["decision_log"]))
          Map.put(merged_sd, "brain", brain)
        else
          merged_sd
        end

        # Sync combat hero_max_hp if hero leveled up mid-combat
        merged_sd = if merged_sd["combat"] && updated_hero.max_hp > (merged_sd["combat"]["hero_max_hp"] || 0) do
          combat = merged_sd["combat"]
          |> Map.put("hero_max_hp", updated_hero.max_hp)
          |> Map.put("hero_hp", updated_hero.hp)
          Map.put(merged_sd, "combat", combat)
        else
          merged_sd
        end

        # 6. S-3: глава дневника — смена дня или перелом (мир/арест/уровень)
        level_up? = updated_hero.level > ctx.hero.level
        breaks = ["world"] ++
          (if level_up?, do: ["level_up"], else: []) ++
          (if merged_sd["jail"], do: ["arrest"], else: [])

        {chapter, chapter_title, journal_state} = TesIdle.Game.Journal.Chapters.ensure(ctx.hero, merged_sd, ctx, breaks)
        merged_sd = Map.put(merged_sd, "journal", journal_state)

        # 6a. S-3: «Новости мира» — до единственного сохранения state_data
        {world_news_entry, merged_sd} =
          case TesIdle.Game.Journal.Chapters.world_news_candidate(updated_hero, merged_sd, ctx) do
            nil -> {nil, merged_sd}
            {event, jstate} ->
              {create_world_news_entry(updated_hero, event, chapter, chapter_title), Map.put(merged_sd, "journal", jstate)}
          end

        # 6b. P-4: сны при долгом отдыхе — до единственного сохранения state_data
        {merged_sd, dream_template} = TesIdle.Game.Sleep.step(merged_sd, updated_hero, result, ctx.configs)
        dream_entry = if dream_template, do: create_dream_entry(updated_hero, dream_template, chapter, chapter_title), else: nil

        # 6c. Periodic auto-equip check (saves state_data as single point)
        equip_events = check_auto_equip(updated_hero, merged_sd)

        # 7. Generate narrative via NarrativeDirector
        # Build context, select event, format via TemplateEngine
        narrative_ctx = NarrativeContext.build(ctx, result)

        journal_entry = if result[:combat_progress] do
          nil
        else
          event = NarrativeDirector.select(narrative_ctx, updated_hero.state_data)
          template_type = event.name
          text = TemplateEngine.format(template_type, narrative_ctx)
          NarrativeDirector.track_used(updated_hero, event.name)

          create_journal_entry(updated_hero, %{type: template_type, text: text}, result, chapter, chapter_title, decision_motive(ctx, merged_sd))
        end

        # Питомцы: усыновление/уход/возрождение — отдельные записи в журнале
        pet_journal_entries = pet_journal(updated_hero, result, pet_events, chapter, chapter_title)

        # 9. Return result for WS push
        {:ok, %{
          state_from: ctx.hero.state,
          state_to: result.state_to,
          narrative: %{type: if(journal_entry, do: journal_entry.entry_type, else: nil), text: if(journal_entry, do: journal_entry.text, else: nil)},
          journal_entry: journal_entry,
          world_news_entry: world_news_entry,
          dream_entry: dream_entry,
          pet_journal_entries: pet_journal_entries,
          combat_progress: result[:combat_progress],
          combat_start: result[:combat_start],
          combat_result: result[:combat_result],
          equip_events: equip_events,
          gold_change: result[:gold_change] || 0,
        }}
      else
        # FSM returned nil result (plan empty, already done).
        # S-2 верификация: state_data (план + decision_log) всё равно нужно
        # сохранять — иначе create_and_execute-тик с мгновенным первым шагом
        # терял и новый план, и запись решения (герой «не помнил» выбор).
        save_state_data(ctx.hero, new_state_data)
        {:ok, %{state_from: ctx.hero.state, state_to: ctx.hero.state, narrative: nil, journal_entry: nil}}
      end
    end
  end

  defp save_state_data(hero, new_state_data) do
    hero
    |> Ecto.Changeset.change(state_data: Jason.encode!(new_state_data))
    |> Repo.update!()

    :ok
  end

  @doc """
  S-4: множители прогрессии применяются к наградам (xp/gold); траты не масштабируются.
  G-1: поверх — гильдейский xp-баф (buff.xp_mult за уровень гильдии).
  """
  def apply_progression(result, configs, guild_buff \\ nil) do
    prog = (configs || %{})["progression"] || %{}
    guild_xp_mult = if is_map(guild_buff), do: (guild_buff["xp_mult"] || 0), else: 0

    xp_gain = trunc((result[:xp] || 0) * (prog["xp_multiplier"] || 1.0) * (1 + guild_xp_mult))

    gold_raw = result[:gold_change] || 0

    gold_gain =
      if gold_raw > 0, do: trunc(gold_raw * (prog["gold_multiplier"] || 1.0)), else: gold_raw

    result
    |> Map.put(:xp, xp_gain)
    |> Map.put(:gold_change, gold_gain)
  end

  defp apply_result(hero, result, configs, guild_buff) do
    # S-4: средний темп — множители из game_configs["progression"] (пустой конфиг → старый темп)
    result = apply_progression(result, configs, guild_buff)
    _needs_delta = configs["needs_delta"] || %{}  # used by mood_cfg indirectly
    mood_cfg = configs["mood"] || %{}

    # Advance game hour (each tick = 0.5-1.5 hours)
    hour_advance = :rand.uniform() * 1.0 + 0.5
    new_hour = hero.game_hour + hour_advance
    new_day = if new_hour >= 24, do: hero.game_day + 1, else: hero.game_day
    new_hour = if new_hour >= 24, do: new_hour - 24, else: new_hour

    # Update needs
    hunger_inc = Enum.random(50..200) / 100.0  # 0.5-2.0
    fatigue_inc = Enum.random(30..100) / 100.0  # 0.3-1.0
    morale_drift = (Enum.random(-50..50)) / 100.0  # -0.5 to 0.5

    new_hunger = min(100, hero.hunger + hunger_inc)
    new_fatigue = min(100, hero.fatigue + fatigue_inc)
    new_morale = max(0, min(100, hero.morale + morale_drift))

    # Morale drain from needs
    new_morale = if new_hunger > 80, do: new_morale - 1.0, else: new_morale
    new_morale = if new_fatigue > 80, do: new_morale - 0.7, else: new_morale
    new_morale = max(0, new_morale)

    # Calculate mood
    mood_base = mood_cfg["base"] || 50
    mood = mood_base + (100 - new_hunger) * (mood_cfg["hunger_weight"] || 0.2)
    mood = mood + (100 - new_fatigue) * (mood_cfg["fatigue_weight"] || 0.15)
    mood = mood + new_morale * (mood_cfg["morale_weight"] || 0.15)
    mood = max(0, min(100, mood + (:rand.uniform() * 10 - 5)))

    # Soul energy regen
    new_soul_energy = min(hero.max_soul_energy || 100, hero.soul_energy + 1.67)

    # Apply all changes
    updates = %{
      state: result.state_to,
      gold: max(0, hero.gold + (result[:gold_change] || 0)),
      hunger: new_hunger,
      fatigue: new_fatigue,
      morale: new_morale,
      mood: mood,
      soul_energy: new_soul_energy,
      game_hour: new_hour,
      game_day: new_day,
      total_play_time_seconds: hero.total_play_time_seconds + Enum.random(15..60),
      total_gold_earned: hero.total_gold_earned + max(0, result[:gold_change] || 0),
      total_kills: hero.total_kills + if(result[:combat_result] && result[:combat_result][:victory], do: 1, else: 0),
      xp: hero.xp + (result[:xp] || 0),
    }

    # Apply HP change if present
    updates = if result[:hp_change] do
      Map.put(updates, :hp, min(hero.max_hp, max(1, hero.hp + result[:hp_change])))
    else
      updates
    end

    # Sync HP from combat state_data during multi-round combat
    updates = if result[:combat_progress] do
      combat_hp = get_in(result, [:combat_progress, :hero_hp])
      if combat_hp do
        new_hp = max(1, combat_hp)
        # Never decrease max_hp — hero may have leveled up
        Map.put(updates, :hp, new_hp)
      else
        updates
      end
    else
      updates
    end

    # Apply MP change if present
    updates = if result[:mp_change] do
      Map.put(updates, :mp, min(hero.max_mp, max(0, hero.mp + result[:mp_change])))
    else
      updates
    end

    # Apply hunger change if present (e.g. window shopping)
    updates = if result[:hunger_change] do
      Map.put(updates, :hunger, max(0, min(100, hero.hunger + result[:hunger_change])))
    else
      updates
    end

    # Фаза 2 (аудит): fatigue_change никогда не применялся — RestAction/TravelAction
    # возвращали снижение усталости в пустоту, fatigue только рос (+0.3–1.0/тик)
    # и застывал на 100 → герой вечно «отдыхал» без эффекта.
    updates = if result[:fatigue_change] do
      Map.put(updates, :fatigue, max(0, min(100, new_fatigue + result[:fatigue_change])))
    else
      updates
    end

    # Apply SP change (travel, combat)
    updates = if result[:sp_change] do
      Map.put(updates, :sp, max(0, min(hero.max_sp, hero.sp + result[:sp_change])))
    else
      updates
    end

    # Apply morale change (socializing)
    updates = if result[:morale_change] do
      Map.put(updates, :morale, max(0, min(100, hero.morale + result[:morale_change])))
    else
      updates
    end

    # Apply location change (travel arrival)
    updates = if result[:location_change] do
      Map.put(updates, :location_id, result[:location_change])
    else
      updates
    end

    # NOTE: state_data is NOT saved here — pipeline handles it as a single save at the end

    # Apply level up
    updates = if updates[:xp] do
      xp = updates[:xp]
      if xp >= hero.xp_to_next do
        new_level = hero.level + 1
        remaining_xp = xp - hero.xp_to_next
        new_xp_to_next = trunc(hero.xp_to_next * (configs["leveling"]["xp_multiplier"] || 1.5))
        attack_base = configs["leveling"]["attack_base"] || 2
        attack_decay = configs["leveling"]["attack_decay"] || 0.01
        defense_base = configs["leveling"]["defense_base"] || 1
        defense_decay = configs["leveling"]["defense_decay"] || 0.01

        updates
        |> Map.put(:level, new_level)
        |> Map.put(:xp, remaining_xp)
        |> Map.put(:xp_to_next, new_xp_to_next)
        |> Map.put(:max_hp, hero.max_hp + (configs["leveling"]["hp_per_level"] || 10))
        |> Map.put(:hp, hero.max_hp + (configs["leveling"]["hp_per_level"] || 10))
        |> Map.put(:attack, hero.attack + max(1, trunc(attack_base / (1 + new_level * attack_decay))))
        |> Map.put(:defense, hero.defense + max(1, trunc(defense_base / (1 + new_level * defense_decay))))
      else
        updates
      end
    else
      updates
    end

    # Мозг: пластичность черт (бюджет) + дрейф связей + возврат к гено-базе
    {personality_update, brain_state} = TesIdle.Game.Brain.Learner.learn(hero, result, configs)
    updates = if personality_update, do: Map.put(updates, :personality, personality_update), else: updates

    updated = Repo.update!(Hero.changeset(hero, updates))
    {updated, brain_state}
  end

  defp create_journal_entry(hero, narrative, result, chapter, chapter_title, motive) do
    is_combat_event = narrative.type in ["hero_victory", "hero_defeat", "enemy_ambush", "spot_bandits", "find_loot", "discover_treasure"]

    entry = Repo.insert!(%JournalEntry{
      hero_id: hero.id,
      entry_type: narrative.type,
      text: narrative.text,
      xp_gained: if(is_combat_event, do: result[:xp] || 0, else: 0),
      gold_gained: if(is_combat_event, do: result[:gold_change] || 0, else: 0),
      monster_name: get_in(result, [:combat_result, :monster_name]) || get_in(result, [:combat_start, :monster_name]),
      location_name: if(Ecto.assoc_loaded?(hero.location) && hero.location, do: hero.location.name, else: ""),
      chapter: chapter,
      chapter_title: chapter_title,
      motive: motive,
    })
    entry
  end

  defp create_world_news_entry(hero, event, chapter, chapter_title) do
    template =
      Repo.one(
        from t in TesIdle.Schemas.NarrativeTemplate,
          where: t.template_type == "world_news" and t.source == "system" and t.is_active == true,
          order_by: fragment("RANDOM()"),
          limit: 1
      )

    text =
      if template do
        template.text_template |> String.replace("{event}", event_name_ru(event))
      else
        "Слухи по Тамриэлю: #{event_name_ru(event)}."
      end

    Repo.insert!(%JournalEntry{
      hero_id: hero.id,
      entry_type: "world_news",
      text: text,
      chapter: chapter,
      chapter_title: chapter_title,
    })
  end

  defp event_name_ru(event), do: event["name"] || event["type"]

  # P-4: запись сна — шаблон из БД (Sleep.step вернул кандидата), нет шаблона — записи нет
  defp create_dream_entry(hero, template, chapter, chapter_title) do
    location_name =
      if Ecto.assoc_loaded?(hero.location) && hero.location, do: hero.location.name, else: ""

    text =
      TesIdle.Game.Narrative.TemplateEngine.render_vars(template.text_template, %{
        "hero_name" => hero.name,
        "location_name" => location_name,
      })

    Repo.insert!(%JournalEntry{
      hero_id: hero.id,
      entry_type: "dream",
      text: text,
      location_name: location_name,
      chapter: chapter,
      chapter_title: chapter_title,
    })
  end

  # S-3: мотив решения — только когда план создан в этом тике (цель изменилась).
  defp decision_motive(ctx, merged_sd) do
    old_goal = case Jason.decode(ctx.hero.state_data || "{}") do
      {:ok, %{"plan" => p}} when is_map(p) -> p["goal"]
      _ -> nil
    end

    new_goal = merged_sd["plan"] && merged_sd["plan"]["goal"]

    if new_goal && new_goal != old_goal do
      TesIdle.Game.Journal.Chapters.motive_for(merged_sd["brain"])
    else
      nil
    end
  end

  # ─── P-2: смерть с таймером и возрождением в ближайшем городе ──────────────

  # Смерть: герой уходит в состояние "dead" с блоком death (respawn_at + ближайший
  # город). Золото теряется сразу (−10%), мозг перерождается при возрождении.
  # Журнал смерти пишет тик поражения (state_to "dead" → тип death из БД).
  defp handle_death(ctx) do
    death_cfg = ctx.configs["death"] || %{}
    respawn_ticks = death_cfg["respawn_ticks"] || 3
    gold_loss = trunc(ctx.hero.gold * (death_cfg["gold_loss_percent"] || 10) / 100)

    city = nearest_city(ctx.hero.location_id)

    state_data = case Jason.decode(ctx.hero.state_data || "{}") do
      {:ok, sd} when is_map(sd) -> sd
      _ -> %{}
    end

    respawn_at =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(respawn_ticks * 60, :second)
      |> NaiveDateTime.truncate(:second)

    death_block = %{
      "respawn_at" => NaiveDateTime.to_iso8601(respawn_at),
      "city_id" => city && city.id,
      "city_name" => city && city.name,
    }

    new_state_data = state_data |> Map.put("death", death_block) |> Jason.encode!()

    _updated =
      Hero.changeset(ctx.hero, %{
        state: "dead",
        hp: 0,
        gold: max(0, ctx.hero.gold - gold_loss),
        state_data: new_state_data,
      })
      |> Repo.update!()

    {:ok, %{
      state_from: ctx.hero.state,
      state_to: "dead",
      narrative: nil,
      journal_entry: nil,
      combat_progress: nil,
      combat_start: nil,
      combat_result: nil,
      equip_events: [],
      gold_change: -gold_loss,
    }}
  end

  # Тик мёртвого героя: до respawn_at — тишина, после — возрождение.
  defp handle_dead_tick(ctx) do
    state_data = case Jason.decode(ctx.hero.state_data || "{}") do
      {:ok, sd} when is_map(sd) -> sd
      _ -> %{}
    end

    case state_data["death"] do
      %{"respawn_at" => iso} = death_block when is_binary(iso) ->
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        case NaiveDateTime.from_iso8601(iso) do
          {:ok, respawn_at} ->
            if NaiveDateTime.compare(now, respawn_at) == :lt do
              dead_silence()
            else
              respawn(ctx, death_block, state_data)
            end

          _ ->
            # битый/нечитаемый timestamp — возрождаем сразу
            respawn(ctx, death_block, state_data)
        end

      _ ->
        # dead без блока (легаси-герои) — ставим блок, ждём дальше
        handle_death(ctx)
    end
  end

  defp dead_silence do
    {:ok, %{
      state_from: "dead",
      state_to: "dead",
      narrative: nil,
      journal_entry: nil,
      combat_progress: nil,
      combat_start: nil,
      combat_result: nil,
      equip_events: [],
      gold_change: 0,
    }}
  end

  # Возрождение: поколение +1 (Learner), телепорт в ближайший город, 20% HP,
  # запись в журнал — только из БД (тип death_respawn), нет шаблона — записи нет.
  defp respawn(ctx, death_block, state_data) do
    death_cfg = ctx.configs["death"] || %{}
    respawn_ratio = death_cfg["respawn_hp_ratio"] || 0.2
    respawn_hp = trunc(ctx.hero.max_hp * respawn_ratio)
    city_id = death_block["city_id"]

    # Мозг: перерождение — поколение +1, черты с мутацией, бюджет обновлён
    {new_personality, new_brain} = TesIdle.Game.Brain.Learner.reborn(ctx.hero, ctx.configs)
    generation = new_brain["generation"] || 1

    sd =
      state_data
      |> Map.delete("death")
      |> Map.put("brain", new_brain)

    # S-3: глава на пробуждении
    {chapter, chapter_title, journal_state} =
      TesIdle.Game.Journal.Chapters.ensure(ctx.hero, sd, ctx, ["world"])

    new_state_data = sd |> Map.put("journal", journal_state) |> Jason.encode!()

    _updated =
      Hero.changeset(ctx.hero, %{
        state: "resting",
        hp: max(1, respawn_hp),
        location_id: city_id || ctx.hero.location_id,
        personality: new_personality,
        state_data: new_state_data,
      })
      |> Repo.update!()

    journal_entry = respawn_journal(ctx, generation, death_block, chapter, chapter_title)

    {:ok, %{
      state_from: "dead",
      state_to: "resting",
      narrative: if(journal_entry, do: %{type: "death_respawn", text: journal_entry.text}, else: nil),
      journal_entry: journal_entry,
      combat_progress: nil,
      combat_start: nil,
      combat_result: nil,
      equip_events: [],
      gold_change: 0,
    }}
  end

  defp respawn_journal(ctx, generation, death_block, chapter, chapter_title) do
    template =
      Repo.one(
        from t in TesIdle.Schemas.NarrativeTemplate,
          where: t.template_type == "death_respawn" and t.is_active == true,
          order_by: fragment("RANDOM()"),
          limit: 1
      )

    case template do
      nil ->
        nil

      template ->
        vars = %{
          "hero_name" => ctx.hero.name,
          "location" => death_block["city_name"] || "",
          "generation" => Integer.to_string(generation),
        }

        text = TesIdle.Game.Narrative.TemplateEngine.render_vars(template.text_template, vars)

        Repo.insert!(%JournalEntry{
          hero_id: ctx.hero.id,
          entry_type: "death_respawn",
          text: text,
          location_name: death_block["city_name"] || "",
          chapter: chapter,
          chapter_title: chapter_title,
        })
    end
  end

  # Ближайший город по map_x/map_y; без координат — первый по алфавиту.
  defp nearest_city(current_location_id) do
    current =
      if current_location_id, do: Repo.get(TesIdle.Schemas.Location, current_location_id), else: nil

    TesIdle.Schemas.Location
    |> where([l], l.location_type == "city")
    |> Repo.all()
    |> case do
      [] -> nil

      cities ->
        cities
        |> Enum.map(fn c -> {c, city_distance(c, current)} end)
        |> Enum.sort_by(fn {c, d} -> {d, c.name} end)
        |> List.first()
        |> elem(0)
    end
  end

  defp city_distance(_city, nil), do: 999_999

  defp city_distance(city, current) do
    if is_number(city.map_x) and is_number(city.map_y) and is_number(current.map_x) and is_number(current.map_y) do
      dx = city.map_x - current.map_x
      dy = city.map_y - current.map_y
      dx * dx + dy * dy
    else
      999_999
    end
  end


  # Питомцы: пассивный тик (голод, лояльность, уход, возрождение)
  defp pet_tick(hero, configs) do
    {_pet, events} = TesIdle.Game.Pets.passive_tick(hero, (configs || %{})["activities"] || %{})
    events
  rescue
    _ -> []
  end

  # Записи в журнале про питомцев: усыновление, уход, возрождение, уход навсегда
  defp pet_journal(hero, result, pet_events, chapter, chapter_title) do
    entries = []

    entries =
      case result[:pet_adopted] do
        %{name: name, species: species} ->
          entry = Repo.insert!(%JournalEntry{
            hero_id: hero.id,
            entry_type: "pet_adopted",
            text: "#{hero.name} приютил #{species_ru(species)}. Назвал его #{name}. Теперь их двое.",
            chapter: chapter,
            chapter_title: chapter_title,
          })
          entries ++ [entry]

        _ -> entries
      end

    Enum.map(pet_events, fn ev ->
      text = case ev.type do
        "pet_left" -> "#{ev.pet_name} больше не вернулся. Лояльность закончилась — питомец ушёл навсегда."
        "pet_revived" -> "#{ev.pet_name} снова на ногах! Раны затянулись, и он догнал героя."
        _ -> nil
      end

      if text do
        Repo.insert!(%JournalEntry{hero_id: hero.id, entry_type: ev.type, text: text, chapter: chapter, chapter_title: chapter_title})
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> then(&(&1 ++ entries))
  end

  defp species_ru("wolf"), do: "волчонка"
  defp species_ru("owl"), do: "совёнка"
  defp species_ru("cat"), do: "котёнка"
  defp species_ru("lizard"), do: "ящерку"
  defp species_ru(other), do: to_string(other)

  defp check_auto_equip(hero, merged_sd) do
    state_data = merged_sd || %{}
    count = Map.get(state_data, "equip_check_count", 0) + 1
    interval = Enum.random(@equip_check_interval)

    if count >= interval do
      new_state = Map.put(state_data, "equip_check_count", 0)
      hero |> Ecto.Changeset.change(%{state_data: Jason.encode!(new_state)}) |> Repo.update!()
      AutoEquip.check_and_equip(hero.id)
    else
      new_state = Map.put(state_data, "equip_check_count", count)
      hero |> Ecto.Changeset.change(%{state_data: Jason.encode!(new_state)}) |> Repo.update!()
      []
    end
  end

  defp auto_consume(hero) do
    hero_id = hero.id

    # HP potion: hero HP < 30%
    if hero.hp < hero.max_hp * 0.3 do
      case find_and_consume(hero_id, :heal_hp) do
        {:ok, item, _inv} ->
          new_hp = min(hero.max_hp, hero.hp + (item.heal_hp || 0))
          hero |> Ecto.Changeset.change(%{hp: new_hp}) |> Repo.update!()
          %{hero | hp: new_hp}
        _ -> hero
      end
    else
      hero
    end
    |> then(fn hero ->
      # Food: hunger > 70
      if hero.hunger > 70 do
        case find_and_consume(hero_id, :reduce_hunger) do
          {:ok, item, _inv} ->
            new_hunger = max(0, hero.hunger - (item.reduce_hunger || 0))
            hero |> Ecto.Changeset.change(%{hunger: new_hunger}) |> Repo.update!()
            %{hero | hunger: new_hunger}
          _ -> hero
        end
      else
        hero
      end
    end)
    |> then(fn hero ->
      # Soul stone: soul_energy < 30
      if hero.soul_energy < 30 do
        case find_and_consume(hero_id, :soul_restore) do
          {:ok, item, _inv} ->
            new_se = min(hero.max_soul_energy || 100, hero.soul_energy + (item.soul_restore || 0))
            hero |> Ecto.Changeset.change(%{soul_energy: new_se}) |> Repo.update!()
            %{hero | soul_energy: new_se}
          _ -> hero
        end
      else
        hero
      end
    end)
  end

  defp find_and_consume(hero_id, field) do
    import Ecto.Query
    alias TesIdle.Schemas.{InventoryItem, Item}

    base_query = from i in Item, where: i.item_type == "consumable" and i.is_active == true

    filtered = case field do
      :heal_hp -> from i in base_query, where: i.heal_hp > 0
      :reduce_hunger -> from i in base_query, where: i.reduce_hunger > 0.0
      :soul_restore -> from i in base_query, where: i.soul_restore > 0.0
      _ -> base_query
    end

    inv = Repo.one(
      from ii in InventoryItem,
        join: i in ^filtered, on: i.id == ii.item_id,
        where: ii.hero_id == ^hero_id and ii.quantity > 0,
        limit: 1,
        select: %{inv: ii, item: i}
    )

    if inv do
      if inv.inv.quantity > 1 do
        inv.inv |> Ecto.Changeset.change(%{quantity: inv.inv.quantity - 1}) |> Repo.update!()
      else
        Repo.delete!(inv.inv)
      end
      {:ok, inv.item, inv.inv}
    else
      :error
    end
  end

  defp maybe_auto_accept_quest(ctx) do
    # Окно активностей: state_data["activity_break_until_tick"] (абсолютный tick).
    # Пока окно не вышло — новый квест не берём, герой живёт своими делами.
    sd = decode_state_data(ctx.hero)
    break_until = sd["activity_break_until_tick"]
    now_tick = current_tick()

    if is_number(break_until) and now_tick < break_until do
      ctx
    else
      auto_accept_quest(ctx)
    end
  end

  defp decode_state_data(hero) do
    case Jason.decode(hero.state_data || "{}") do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end

  # Абсолютный счётчик тиков ядра мира (снапшот несёт tick); офлайн/тест —
  # fallback: грубая оценка по игровому дню (1 день ≈ 24 тика).
  defp current_tick do
    snap = TesIdle.World.Kernel.snapshot()
    if is_map(snap) and is_number(snap["tick"]) do
      snap["tick"]
    else
      0
    end
  end

  defp auto_accept_quest(ctx) do
    alias TesIdle.Schemas.{Quest, QuestStep, ActiveQuest}

    # Find a random quest
    quest = Repo.one(from q in Quest, where: q.is_active == true, order_by: fragment("RANDOM()"), limit: 1)
    if quest do
      case Repo.insert(%ActiveQuest{hero_id: ctx.hero.id, quest_id: quest.id}) do
        {:ok, aq} ->
          %{ctx | active_quest: aq}
        _ ->
          ctx
      end
    else
      ctx
    end
  end

  defp track_memories(hero, action_module, result, state_data) do
    sd = state_data || %{}
    memories = Map.get(sd, "memories", [])

    new_memories = case action_module do
      TesIdle.Game.Actions.FightAction ->
        if result[:combat_result] do
          combat = result[:combat_result]
          entry = if combat[:victory] do
            %{"type" => "victory", "monster" => combat[:monster_name] || "враг",
              "day" => hero.game_day, "gold_earned" => combat[:gold] || 0, "mood_impact" => 10}
          else
            %{"type" => "defeat", "monster" => combat[:monster_name] || "враг",
              "day" => hero.game_day, "gold_lost" => 0, "mood_impact" => -20}
          end
          memories ++ [entry]
        else
          memories
        end

      TesIdle.Game.Actions.ExploreAction ->
        if result[:gold_change] && result[:gold_change] > 0 do
          memories ++ [%{"type" => "discovery", "what" => "здесь было найдено золото", "day" => hero.game_day, "mood_impact" => 15}]
        else
          memories
        end

      TesIdle.Game.Actions.SocialAction ->
        memories ++ [%{"type" => "social", "npc" => "спутник", "day" => hero.game_day, "mood_impact" => 8}]

      TesIdle.Game.Actions.ShopAction ->
        if result[:item_name] do
          memories ++ [%{"type" => "shop", "item" => result[:item_name], "day" => hero.game_day, "gold_spent" => result[:gold_spent] || 0, "mood_impact" => 5}]
        else
          memories
        end

      TesIdle.Game.Actions.TravelAction ->
        if result[:events] && Enum.any?(result[:events] || [], &String.starts_with?(&1, "arrived_")) do
          memories ++ [%{"type" => "travel", "destination" => "arrived", "day" => hero.game_day, "mood_impact" => 3}]
        else
          memories
        end

      _ ->
        memories
    end

    new_memories = Enum.take(new_memories, -20)
    updated_sd = Map.put(sd, "memories", new_memories)
    {hero, updated_sd}
  end

  # 5b. Quest progress tracking. true — квест завершён полностью (Фаза 2:
  # caller ставит «окно активностей» в merged_sd — правило единственного писателя).
  defp check_quest_progress(hero, action_module, result) do
    alias TesIdle.Schemas.{ActiveQuest, QuestStep, Quest}

    aq = Repo.one(from aq in ActiveQuest, where: aq.hero_id == ^hero.id, limit: 1)
    if aq do
      progress_quest(hero, aq, action_module, result)
    else
      false
    end
  end

  defp progress_quest(hero, aq, action_module, result) do
    alias TesIdle.Schemas.{QuestStep, Quest}

    step = Repo.one(
      from s in QuestStep,
        where: s.quest_id == ^aq.quest_id and s.step_order == ^aq.current_step,
        limit: 1
    )

    if step do
      # Map action modules to step types
      action_to_step = %{
        TesIdle.Game.Actions.FightAction => "kill",
        TesIdle.Game.Actions.ExploreAction => "explore",
        TesIdle.Game.Actions.ShopAction => "collect",
        TesIdle.Game.Actions.TravelAction => "travel",
      }

      expected_type = Map.get(action_to_step, action_module)

      if expected_type && step.step_type == expected_type do
        # Фаза 3 (аудит E): kill-прогресс считался КАЖДЫЙ раунд боя —
        # шаг kill выполнялся за один multi-tick. Раунды приходят с
        # combat_progress и без combat_result — их пропускаем; победу
        # (combat_result) и не-боевые действия считаем как раньше.
        round_only? = action_module == TesIdle.Game.Actions.FightAction and
                      result[:combat_result] == nil and result[:combat_progress] != nil

        if round_only? do
          false
        else
          new_progress = aq.current_progress + 1

          if new_progress >= step.target_count do
            # Step complete — advance to next or complete quest
            total_steps = Repo.one(
              from s in QuestStep,
                where: s.quest_id == ^aq.quest_id,
                select: count()
            )
            if aq.current_step >= total_steps do
              # Quest complete — all steps done
              quest = Repo.one(from q in Quest, where: q.id == ^aq.quest_id)
              if quest do
                # Award rewards
                updated_quest_hero =
                  hero
                  |> Hero.changeset(%{
                    xp: hero.xp + quest.xp_reward,
                    gold: hero.gold + quest.gold_reward,
                  })
                  |> Repo.update!()

                # P-3: репутация фракции региона растёт от завершённых квестов
                reputation_reward(updated_quest_hero, configs_hero_location(hero), "quest_complete")

                # Bonus item reward for harder quests
                if quest.difficulty >= 3 do
                  alias TesIdle.Schemas.{Item, InventoryItem}
                  heal_item = Repo.one(from i in Item, where: i.name == "Healing Potion" or i.name == "Зелье здоровья" or i.item_type == "potion", limit: 1)
                  if heal_item do
                    existing = Repo.one(from ii in InventoryItem, where: ii.hero_id == ^hero.id and ii.item_id == ^heal_item.id)
                    if existing do
                      existing |> Ecto.Changeset.change(%{quantity: existing.quantity + 2}) |> Repo.update!()
                    else
                      Repo.insert!(%InventoryItem{hero_id: hero.id, item_id: heal_item.id, quantity: 2})
                    end
                  end
                end
              end
              Repo.delete!(aq)
              true
            else
              # Next step
              aq
              |> Ecto.Changeset.change(%{current_step: aq.current_step + 1, current_progress: 0})
              |> Repo.update!()
              false
            end
          else
            # Increment progress
            aq
            |> Ecto.Changeset.change(%{current_progress: new_progress})
            |> Repo.update!()
            false
          end
        end
      else
        false
      end
    else
      false
    end
  end

  # Фаза 2: «окно активностей» — 3–5 тиков без auto_accept после квеста.
  defp activity_break_ticks, do: 3 + :rand.uniform(3) - 1

  # --- P-3: репутация — позитивные источники ---------------------------------

  # Победа в бою: маленький плюс фракции региона (герой чистит землю)
  defp reputation_tick(ctx, action_module, result)
       when action_module == TesIdle.Game.Actions.FightAction do
    if result[:combat_result] && result[:combat_result][:victory] do
      reputation_reward(ctx.hero, ctx, "monster_kill")
    end
  end

  defp reputation_tick(_ctx, _action_module, _result), do: :ok

  # Единая точка: +delta фракции региона героя по конфигу reputation
  defp reputation_reward(hero, ctx_like, kind) do
    rep_cfg = TesIdle.Game.Law.rep_cfg(ctx_like.configs)
    delta = rep_cfg[kind] || 0
    if is_number(delta) and delta > 0 and hero.location_id do
      faction = TesIdle.Game.Law.faction_for(ctx_like)
      TesIdle.Game.Law.adjust_reputation(hero.id, faction, delta, ctx_like.configs, hero.name)
    end
  end

  # Внутри check_quest_progress у нас нет ctx — собираем минимальный аналог
  defp configs_hero_location(hero) do
    location = if hero.location_id, do: Repo.one(from l in TesIdle.Schemas.Location, where: l.id == ^hero.location_id, limit: 1)
    %{configs: ContextBuilder.load_configs(), location: location, hero: hero}
  end
end

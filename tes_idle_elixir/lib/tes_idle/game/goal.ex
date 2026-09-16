defmodule TesIdle.Game.Goal do
  @moduledoc """
  Utility AI: evaluates all goals and picks the highest utility.
  Each goal's utility is influenced by personality traits, needs, and memories.
  """

  alias TesIdle.Game.{Personality, Memory}

  defstruct [:name, :utility, :reason, :target_location_id, :brain_reasons]

  @doc "S-2 стадия 1: базовые цели (needs/personality/memory) — без обогащения."
  def base_goals(ctx) do
    [
      eval_quest(ctx),
      eval_heal(ctx),
      eval_rest(ctx),
      eval_explore(ctx),
      eval_fight(ctx),
      eval_shop(ctx),
      eval_socialize(ctx),
      eval_travel(ctx),
      eval_loot(ctx),
      eval_fish(ctx),
      eval_gather(ctx),
      eval_steal(ctx),
      eval_break_in(ctx),
      eval_pet_care(ctx),
    ]
    |> Enum.reject(fn g -> g.utility <= 0 end)
  end

  @doc "Evaluate all goals and return sorted by utility (descending)."
  def evaluate_all(ctx) do
    ctx
    |> base_goals()
    |> TesIdle.Game.Brain.Graph.enrich(ctx)
    |> Enum.sort_by(fn g -> -g.utility end)
  end

  @doc "Get the best goal. S-2: делегирует единому ядру решений (Brain.Intent)."
  def best(ctx) do
    case TesIdle.Game.Brain.Intent.evaluate(ctx) do
      [best | _] -> best
      [] -> %__MODULE__{name: :explore, utility: 0.3, reason: "Ничего лучшего нет"}
    end
  end

  # --- Individual goal evaluators ---

  # Аудит поведения 2026-09 (Фаза 2): критические нужды бьют квест.
  # Godville-принцип: сначала поспать/подлечиться, потом подвиги.
  # Пороги — из game_configs["needs_urgent"] (fallback: fatigue 75, hp 50%).
  defp urgent_needs?(ctx) do
    urg = get_in(ctx.configs || %{}, ["needs_urgent"]) || %{}
    fatigue_threshold = urg["fatigue"] || 75
    hp_threshold = urg["hp_ratio"] || 0.5
    hp_ratio = ctx.hero.hp / max(1, ctx.hero.max_hp)
    ctx.needs.fatigue > fatigue_threshold or hp_ratio < hp_threshold
  end

  # Сон/лечение — жёсткий приоритет при критических нуждах: rest/heal
  # получают уверенный бонус, quest режется (см. eval_quest).
  defp rest_boost(ctx) do
    urg = get_in(ctx.configs || %{}, ["needs_urgent"]) || %{}
    boost = urg["rest_boost"] || 0.35

    hp_ratio = ctx.hero.hp / max(1, ctx.hero.max_hp)
    cond do
      hp_ratio < (urg["hp_ratio"] || 0.5) -> boost
      ctx.needs.fatigue > (urg["fatigue"] || 75) -> boost
      true -> 0.0
    end
  end

  defp eval_quest(ctx) do
    case ctx.active_quest do
      nil ->
        %__MODULE__{name: :complete_quest, utility: 0.0, reason: "Нет активного квеста"}
      _aq ->
        # Фаза 2: base 0.7 → 0.45 (квест не должен автоматически выигрывать
        # у всех активностей). Близость шага возвращает до +0.25.
        base = 0.45
        personality = ctx.personality
        tenacity_mod = Personality.trait(personality, :tenacity) * 0.0015

        # Quest step type bonus (награда за правильное место/шаг)
        step_type = get_quest_step_type(ctx)
        location_match = case step_type do
          "explore" -> if(ctx.location_type in ["wilderness", "dungeon", "village"], do: 0.15, else: 0.0)
          "kill" -> if(ctx.location_type in ["wilderness", "dungeon"], do: 0.2, else: 0.0)
          "collect" -> if(ctx.location_type in ["city", "village"] && ctx.location && ctx.location.has_shop, do: 0.25, else: -0.2)
          "travel" -> 0.2
          _ -> 0.0
        end

        # Критические нужды: квест подождёт (запас после Graph-кэпа ±0.15 —
        # quest всё равно не вернётся выше ~0.3+0.15 < rest 0.4+0.35).
        urgent_cut = if urgent_needs?(ctx), do: -0.3, else: 0.0

        utility = base + tenacity_mod + location_match + urgent_cut
        reason_suffix = if urgent_needs?(ctx), do: " · сил нет, потом", else: ""
        %__MODULE__{
          name: :complete_quest,
          utility: min(1.0, max(0.0, utility)),
          reason: "Квест: #{get_quest_name(ctx)}#{reason_suffix}",
        }
    end
  end

  defp eval_heal(ctx) do
    hp_ratio = ctx.hero.hp / max(1, ctx.hero.max_hp)
    if hp_ratio < 0.5 do
      caution = Personality.trait(ctx.personality, :caution)
      # Фаза 2: лечение — тот же жёсткий приоритет, что и сон (см. rest_boost):
      # герой с hp < 50% сначала лечится, а не завершает квест.
      utility = (1.0 - hp_ratio) * 0.8 + caution * 0.005 + rest_boost(ctx)
      %__MODULE__{name: :heal, utility: min(1.0, utility), reason: "HP низкий: #{trunc(hp_ratio * 100)}%"}
    else
      %__MODULE__{name: :heal, utility: 0.0, reason: "HP достаточный"}
    end
  end

  defp eval_rest(ctx) do
    needs = ctx.needs
    caution = Personality.trait(ctx.personality, :caution)
    utility = needs.fatigue * 0.004 + needs.hunger * 0.003 + caution * 0.003

    # Night bonus
    utility = if ctx.hour >= 22 or ctx.hour < 6, do: utility + 0.15, else: utility

    # Already resting — boost
    utility = if ctx.hero.state == "resting", do: utility + 0.2, else: utility

    # Фаза 2: критические нужды → жёсткий приоритет сна/лечения
    utility = utility + rest_boost(ctx)

    %__MODULE__{name: :rest, utility: min(1.0, utility), reason: "Усталость: #{trunc(needs.fatigue)}%"}
  end

  defp eval_explore(ctx) do
    curiosity = Personality.trait(ctx.personality, :curiosity)
    base = 0.3
    curiosity_mod = curiosity * 0.004
    memory_mod = Memory.explore_modifier(ctx.hero) * 0.02

    # Night penalty
    utility = if ctx.hour >= 22 or ctx.hour < 6, do: base - 0.15, else: base

    utility = utility + curiosity_mod + memory_mod

    %__MODULE__{name: :explore, utility: min(1.0, max(0.0, utility)), reason: "Исследование"}
  end

  defp eval_fight(ctx) do
    bravery = Personality.trait(ctx.personality, :bravery)
    caution = Personality.trait(ctx.personality, :caution)

    # Already in combat — must fight
    if ctx.combat_state do
      %__MODULE__{name: :fight, utility: 1.0, reason: "В бою!"}
    else
      hp_ratio = ctx.hero.hp / max(1, ctx.hero.max_hp)

      # Фаза 2: порог отказа от боя 0.3 → 0.45 (285 passed-аудит: герой лез
      # в бой с 30% HP и попадал в цикл hero_defeat; 0.45 даёт запас на раунды).
      if hp_ratio > 0.45 and monsters_here?(ctx) do
        base = 0.4
        bravery_mod = bravery * 0.004
        caution_mod = caution * (-0.002)
        memory_mod = Memory.fight_modifier(ctx.hero) * 0.01
        location_bonus = if ctx.location_type in ["dungeon", "wilderness"], do: 0.15, else: 0.0

        # W-5: плотность монстров мира (±0.15 кэп)
        density_mod = world_density_mod(ctx)

        utility = base + bravery_mod + caution_mod + memory_mod + location_bonus + density_mod
        %__MODULE__{name: :fight, utility: min(1.0, max(0.0, utility)), reason: "Бой"}
      else
        %__MODULE__{name: :fight, utility: 0.0, reason: "Врагов рядом нет"}
      end
    end
  end

  # Плотность локации из снапшота мира → модификатор utility боя (кэп ±0.15)
  defp world_density_mod(ctx) do
    with world when is_map(world) <- ctx.world,
         loc_id when is_binary(loc_id) <- ctx.hero.location_id,
         d when is_number(d) <- get_in(world, ["density", loc_id]) do
      ((d - 1.0) * 0.15) |> max(-0.15) |> min(0.15)
    else
      _ -> 0.0
    end
  end

  # Есть ли живые монстры на текущей локации (иначе fight не выбирается — герой не циклится)
  defp monsters_here?(ctx) do
    alias TesIdle.Repo
    alias TesIdle.Schemas.Monster
    import Ecto.Query

    if ctx.hero.location_id do
      Repo.exists?(from m in Monster, where: m.location_id == ^ctx.hero.location_id and m.is_active == true)
    else
      false
    end
  end

  defp eval_shop(ctx) do
    greed = Personality.trait(ctx.personality, :greed)
    hunger = ctx.needs.hunger
    has_shop = ctx.location && ctx.location.has_shop

    if has_shop && hunger > 50 do
      utility = hunger * 0.002 + greed * 0.004 + (if ctx.hero.gold > 0, do: 0.1, else: 0.0)
      %__MODULE__{name: :shop, utility: min(1.0, utility), reason: "Магазин"}
    else
      %__MODULE__{name: :shop, utility: 0.0, reason: "Нет магазина"}
    end
  end

  defp eval_socialize(ctx) do
    sociability = Personality.trait(ctx.personality, :sociability)
    morale = ctx.needs.morale
    has_inn = ctx.location && ctx.location.has_inn

    if has_inn do
      base = 0.2
      sociability_mod = sociability * 0.005
      morale_mod = (100 - morale) * 0.003
      evening_bonus = if ctx.hour >= 18 and ctx.hour < 22, do: 0.15, else: 0.0

      utility = base + sociability_mod + morale_mod + evening_bonus
      %__MODULE__{name: :socialize, utility: min(1.0, utility), reason: "Общение"}
    else
      %__MODULE__{name: :socialize, utility: 0.0, reason: "Нет таверны"}
    end
  end

  defp eval_travel(ctx) do
    curiosity = Personality.trait(ctx.personality, :curiosity)

    # Don't travel if already traveling
    if ctx.travel_state do
      %__MODULE__{name: :travel, utility: 0.0, reason: "Уже в пути"}
    else
      # Фаза 2 (аудит): квестовый тяги к путешествию — только если текущий
      # шаг НЕвыполним на этой локации. Раньше любой город/деревня давал +0.5
      # (грубый стаб needs_different_location?) — герой с ослабленным квестом
      # метался между населёнными пунктами, не выполняя шаг.
      quest_need =
        if ctx.active_quest do
          if quest_step_needs_move?(ctx), do: 0.5, else: 0.0
        else
          0.0
        end

      curiosity_mod = curiosity * 0.003
      utility = 0.1 + curiosity_mod + quest_need
      %__MODULE__{name: :travel, utility: min(1.0, utility), reason: "Путешествие"}
    end
  end

  # Текущий шаг квеста нельзя сделать на этой локации → пора в путь.
  defp quest_step_needs_move?(ctx) do
    case get_quest_step_type(ctx) do
      "explore" -> not (ctx.location_type in ["wilderness", "dungeon", "village"])
      "kill" -> not (ctx.location_type in ["wilderness", "dungeon"])
      "collect" -> not (ctx.location_type in ["city", "village"] && ctx.location && ctx.location.has_shop)
      "travel" -> needs_different_location?(ctx)
      _ -> false
    end
  end

  defp eval_loot(ctx) do
    greed = Personality.trait(ctx.personality, :greed)
    location_bonus = if ctx.location_type in ["dungeon", "wilderness"], do: 0.15, else: 0.0

    utility = 0.15 + greed * 0.003 + location_bonus
    %__MODULE__{name: :loot, utility: min(1.0, utility), reason: "Поиск добычи"}
  end

  # --- Фаза 2: новые активности ---

  defp eval_fish(ctx) do
    flags = (ctx.location && ctx.location.flags) || %{}

    if flags["water"] do
      patience = Personality.trait(ctx.personality, :patience)
      hunger = ctx.needs.hunger

      base = 0.25 + patience * 0.004 + hunger * 0.002
      # Рассвет — клёв (и любимое время dawn_fisher)
      dawn = if ctx.hour >= 5 and ctx.hour <= 8, do: 0.1, else: 0.0
      utility = base + dawn

      %__MODULE__{name: :fish, utility: min(1.0, utility), reason: "Рыбалка у воды"}
    else
      %__MODULE__{name: :fish, utility: 0.0, reason: "Рядом нет воды"}
    end
  end

  defp eval_gather(ctx) do
    flags = (ctx.location && ctx.location.flags) || %{}
    can_gather = flags["gather_nodes"] == true or ctx.location_type in ["wilderness", "village"]

    if can_gather do
      curiosity = Personality.trait(ctx.personality, :curiosity)
      patience = Personality.trait(ctx.personality, :patience)

      utility = 0.25 + curiosity * 0.002 + patience * 0.002 + if(flags["gather_nodes"], do: 0.1, else: 0.0)
      %__MODULE__{name: :gather, utility: min(1.0, utility), reason: "Собирательство"}
    else
      %__MODULE__{name: :gather, utility: 0.0, reason: "Нечего собирать"}
    end
  end

  defp eval_steal(ctx) do
    greed = Personality.trait(ctx.personality, :greed)
    dexterity = Personality.trait(ctx.personality, :dexterity)
    caution = Personality.trait(ctx.personality, :caution)

    if ctx.location_type in ["city", "village"] do
      base = -0.05 + greed * 0.005 + dexterity * 0.002 - caution * 0.002
      night = if ctx.hour >= 22 or ctx.hour < 6, do: 0.1, else: 0.0

      # Осторожный не пойдёт воровать с большой наградой за голову
      bounty_penalty =
        if caution > 60 and TesIdle.Game.Law.total_bounty(ctx.hero) > 100, do: -0.25, else: 0.0

      utility = base + night + bounty_penalty
      %__MODULE__{name: :steal, utility: min(1.0, max(0.0, utility)), reason: "Лёгкие чужие деньги"}
    else
      %__MODULE__{name: :steal, utility: 0.0, reason: "Воровать негде"}
    end
  end

  defp eval_break_in(ctx) do
    flags = (ctx.location && ctx.location.flags) || %{}

    if flags["locked_buildings"] == true do
      curiosity = Personality.trait(ctx.personality, :curiosity)
      dexterity = Personality.trait(ctx.personality, :dexterity)
      has_tool = Enum.any?(ctx.inventory || [], fn {_inv, item} -> "lockpick" in (item.tags || []) end)

      base = 0.05 + curiosity * 0.004 + dexterity * 0.003 + if(has_tool, do: 0.15, else: 0.0)
      %__MODULE__{name: :break_in, utility: min(1.0, max(0.0, base)), reason: "Запертые двери"}
    else
      %__MODULE__{name: :break_in, utility: 0.0, reason: "Нечего вскрывать"}
    end
  end

  defp eval_pet_care(ctx) do
    # hero.id отсутствует у «свежесобранного» героя (тесты/структуры) — не ходим в БД
    pet = if ctx.hero && ctx.hero.id, do: TesIdle.Game.Pets.active(ctx.hero.id), else: nil

    if pet do
      empathy = Personality.trait(ctx.personality, :empathy)
      neglect = max(pet.hunger, 100 - pet.loyalty) + max(0.0, 50 - pet.mood)

      utility = 0.08 + neglect * 0.004 + empathy * 0.003
      %__MODULE__{name: :pet_care, utility: min(1.0, utility), reason: "Ухаживает за #{pet.name}"}
    else
      %__MODULE__{name: :pet_care, utility: 0.0, reason: "Питомца нет"}
    end
  end

  # --- Helpers ---

  defp get_quest_step_type(ctx) do
    alias TesIdle.Repo
    alias TesIdle.Schemas.QuestStep
    import Ecto.Query

    if ctx.active_quest do
      step = Repo.one(
        from s in QuestStep,
          where: s.quest_id == ^ctx.active_quest.quest_id and s.step_order == ^ctx.active_quest.current_step,
          limit: 1,
          select: s.step_type
      )
      step || "explore"
    else
      "explore"
    end
  end

  defp get_quest_name(ctx) do
    alias TesIdle.Repo
    alias TesIdle.Schemas.Quest
    import Ecto.Query

    if ctx.active_quest do
      quest = Repo.one(from q in Quest, where: q.id == ^ctx.active_quest.quest_id, select: q.name)
      quest || "Неизвестный квест"
    else
      "Нет квеста"
    end
  end

  defp needs_different_location?(ctx) do
    # Simplified: check if current location doesn't have monsters at hero level
    ctx.location_type == "village" || ctx.location_type == "city"
  end
end

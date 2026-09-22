defmodule TesIdle.Game.ContextBuilder do
  @moduledoc """
  Builds a GameContext from database state.
  All DB queries happen here — no queries in Actions or DecisionMaker.
  """

  alias TesIdle.Repo
  alias TesIdle.Game.GameContext
  alias TesIdle.Schemas.{Hero, InventoryItem, ActiveQuest, GameConfig}
  import Ecto.Query

  @location_profiles %{
    "city" => %{
      "exploring" => 15,
      "fighting" => 10,
      "looting" => 5,
      "resting" => 20,
      "shopping" => 20,
      "socializing" => 20,
      "traveling" => 10
    },
    "village" => %{
      "exploring" => 20,
      "fighting" => 10,
      "looting" => 5,
      "resting" => 20,
      "shopping" => 15,
      "socializing" => 15,
      "traveling" => 15
    },
    "dungeon" => %{
      "exploring" => 25,
      "fighting" => 45,
      "looting" => 20,
      "resting" => 5,
      "shopping" => 0,
      "socializing" => 0,
      "traveling" => 5
    },
    "wilderness" => %{
      "exploring" => 35,
      "fighting" => 30,
      "looting" => 15,
      "resting" => 10,
      "shopping" => 0,
      "socializing" => 0,
      "traveling" => 10
    }
  }

  def build(hero_id) do
    hero = Repo.get!(Hero, hero_id) |> Repo.preload([:location, :equipment])
    location = hero.location

    inventory =
      Repo.all(
        from i in InventoryItem,
          where: i.hero_id == ^hero_id,
          join: item in assoc(i, :item),
          select: {i, item}
      )

    active_quest = Repo.get_by(ActiveQuest, hero_id: hero_id)
    state_data = parse_state_data(hero.state_data)
    configs = load_configs()

    # --- Фаза 3: мир (ETS-снапшот, атомарное чтение) ---
    world = TesIdle.World.Snapshot.current()
    weather = world_weather(world, location)

    # Apply weather effects (мировая погода; legacy location.weather как fallback)
    {hunger, fatigue, morale} =
      apply_weather(location, weather, hero.hunger, hero.fatigue, hero.morale)

    %GameContext{
      hero: hero,
      location: location,
      configs: configs,
      inventory: inventory,
      equipment: hero.equipment,
      active_quest: active_quest,
      hour: hero.game_hour,
      location_type: if(location, do: location.location_type, else: "wilderness"),
      mood: hero.mood,
      needs: %{
        hunger: hunger,
        fatigue: fatigue,
        morale: morale
      },
      combat_state: state_data["combat"],
      travel_state: state_data["travel"],
      equip_events: [],
      personality: TesIdle.Game.Personality.normalize(hero.personality),
      plan: state_data["plan"],
      memories: TesIdle.Game.Memory.get_memories(hero),
      state_data: state_data,
      weather: weather,
      world: world,
      # G-1: баф гильдии (nil вне гильдии) — XP-множитель в apply_progression,
      # атака/HP — в бою (fight_action)
      guild_buff: TesIdle.Game.Guilds.buff_for_user(hero.user_id, configs)
    }
  end

  # Погода региона из снапшота ядра; без региона/без мира — "clear"
  defp world_weather(_world, nil), do: "clear"

  defp world_weather(world, location) do
    region = location.region
    w = get_in(world, ["weather", region])
    if w in TesIdle.World.Snapshot.weathers(), do: w, else: "clear"
  end

  defp apply_weather(nil, _world_weather, h, f, m), do: {h, f, m}

  defp apply_weather(_location, world_weather, hunger, fatigue, morale) do
    # Погода ядра мира — единственный источник (legacy location.weather не читаем)
    {h, f, m} = TesIdle.World.Weather.needs_effects(world_weather)
    {hunger + h, min(100, fatigue + f), max(0, morale + m)}
  end

  @doc "Загружает все game_configs (публично — используется и тестами)."
  def load_configs do
    db_configs = Repo.all(from c in GameConfig, select: {c.key, c.value})

    defaults = %{
      "location_profiles" => @location_profiles,
      "needs" => %{
        "hunger_high" => 70,
        "fatigue_high" => 70,
        "morale_low" => 30,
        "hp_low_ratio" => 0.3
      },
      # Фаза 2 (аудит поведения): критические нужды бьют квест — rest/heal
      # приоритетны при fatigue > 75 или hp < 50% (см. Goal.urgent_needs?/1)
      "needs_urgent" => %{"fatigue" => 75, "hp_ratio" => 0.5, "rest_boost" => 0.35},
      "needs_delta" => %{
        "hunger_increase" => [0.5, 2.0],
        "fatigue_increase" => [0.3, 1.0],
        "morale_drift" => [-0.5, 0.5]
      },
      "mood" => %{
        "base" => 50,
        "hunger_weight" => 0.2,
        "fatigue_weight" => 0.15,
        "morale_weight" => 0.15
      },
      "combat" => %{"level_range" => 2, "damage_variance" => [-3, 5]},
      "leveling" => %{
        "xp_multiplier" => 1.5,
        "hp_per_level" => 10,
        "attack_base" => 2,
        "attack_decay" => 0.01,
        "defense_base" => 1,
        "defense_decay" => 0.01
      },
      "progression" => %{"xp_multiplier" => 0.5, "gold_multiplier" => 0.75, "skill_rate" => 0.5},
      "resting" => %{"heal_range" => [10, 30], "fatigue_reduction" => [10, 25]},
      "shopping" => %{"cost" => 10, "hunger_reduction" => [15, 30]},
      "socializing" => %{
        "morale_gain" => [3, 8],
        "gamble_chance" => 0.15,
        "gamble_gold_range" => [5, 30]
      },
      "travel" => %{
        "fatigue_cost" => 15,
        "gold_cost" => 5,
        "sp_cost" => 10,
        "tick_fatigue_cost" => 3,
        "tick_sp_cost" => 2,
        "ticks" => [2, 5],
        "encounter_chance" => %{
          "dungeon" => 0.30,
          "wilderness" => 0.20,
          "village" => 0.10,
          "city" => 0.05,
          "default" => 0.10
        }
      },
      "death" => %{"gold_loss_percent" => 10, "respawn_hp_ratio" => 0.2, "respawn_ticks" => 3},
      "memory" => %{"max_entries" => 20},
      "sleep" => %{"dream_chance" => 0.35, "min_streak" => 3},
      # S-7: политика хроники. По умолчанию очистка ВЫКЛЮЧЕНА и в dry-run,
      # троттлинг — в shadow (считает, но ничего не подавляет): включение
      # сокращения истории требует осознанного решения администратора.
      "journal_retention" => %{
        "enabled" => false,
        "dry_run" => true,
        "routine_days" => 7,
        "keep_last_routine" => 500,
        "warning_rows_per_hero" => 10_000,
        "batch_size" => 1000
      },
      "journal_throttle" => %{
        "mode" => "shadow",
        "ambient_type_cooldown_seconds" => 600,
        "ambient_per_hour" => 6
      },
      # Искры — редкая валюта игрока. Числа гипотеза, правятся без выкладки кода.
      "soul_sparks" => %{
        "time_daily" => 1,
        "victory_daily" => 2,
        "quest_weekly" => 2,
        "guild_weekly" => 1,
        "victory_chance" => 0.12,
        "time_chance" => 0.02,
        "guild_min_level" => 2,
        "guild_points" => 50,
        "dossier_cost" => 1,
        "rank_costs" => [1, 2, 4]
      },
      # Встречи героев: единый runtime fallback для EncounterWorker/Resolver.
      "encounters" => %{
        "round_seconds" => 60,
        "activity_ttl_seconds" => 120,
        "allowed_states" => ["exploring", "resting", "socializing", "shopping"],
        "daily_cap" => 10,
        "cooldown_seconds" => 300,
        "familiarity_gain" => 1,
        "fallback_label" => "Попутчик",
        "kind" => "meeting"
      },
      "brain" => %{
        "enabled" => true,
        "link_gain" => 0.35,
        "cap" => 0.15,
        "plasticity_week" => 10.0,
        "drift_up" => 0.01,
        "drift_down" => 0.015,
        "drift_range" => 0.3,
        # C-3: возврат к гено-базе раз в игровой день (0.02/тик съедал бюджет пластичности)
        "base_return" => 0.02,
        "rebirth_mutation" => 5,
        # Brain v2: устойчивое намерение, анти-повторы и чистая outcome-фрустрация.
        "audit" => %{
          "enabled" => true
        },
        "intent" => %{
          "enabled" => true,
          "switch_margin" => 0.08,
          "min_hold_decisions" => 2,
          "repeat_window" => 5,
          "repeat_penalty" => 0.025,
          "frustration_step" => 0.08,
          "frustration_max" => 0.32,
          "novelty" => 0.0001
        }
      },
      "journal" => %{
        "break_events" => ["war_declared", "dragon", "eclipse", "monster_wave"],
        "news_events" => ["war_declared", "dragon", "eclipse", "monster_wave", "fair"],
        "news_chance" => 0.25,
        "titles" => %{
          "day" => "Тихий день",
          "war_declared" => "Война за холмами",
          "dragon" => "Дракон в небе",
          "eclipse" => "Дни без солнца",
          "monster_wave" => "Нечисть выходит из пустошей",
          "arrest" => "Цена чужого добра",
          "level_up" => "Новая ступень"
        }
      },
      "activities" => %{
        "exploration" => %{
          "encounter_chance" => %{
            "wilderness" => 0.12,
            "dungeon" => 0.20,
            "village" => 0.04,
            "city" => 0.02
          }
        },
        "fishing" => %{
          "catch_chance" => 0.45,
          "weather_scale" => 1.0,
          "dawn_bonus" => 0.15,
          "dawn_hours" => [5, 8],
          "ticks" => [1, 5],
          "skill_xp" => 1,
          "xp" => [3, 8]
        },
        "gathering" => %{
          "find_chance" => 0.55,
          "skill_xp" => 1,
          "xp" => [2, 6]
        },
        "mining" => %{
          "ticks" => [2, 4],
          "find_chance" => 0.6,
          "skill_xp" => 1,
          "xp" => [3, 7],
          "goal_base" => 0.15,
          "patience_weight" => 0.003,
          "dexterity_weight" => 0.003,
          "curiosity_weight" => 0.002,
          "ore_nodes_bonus" => 0.1
        },
        "stealing" => %{
          "witness_base" => 0.35,
          "guard_skill" => 30,
          "night_bonus" => 0.15,
          "eclipse_bonus" => 0.25,
          "fair_guard_multiplier" => 1.2,
          "bounty_per_crime" => [15, 40],
          "fine_multiplier" => 2,
          "arrest_bounty" => 50,
          "rep_loss" => [5, 15],
          "skill_xp" => 1
        },
        "breaking_in" => %{
          "trap_chance" => 0.35,
          "noise_chance" => 0.30,
          "trap_hp" => [5, 15],
          "loot_gold" => [20, 80],
          "lockpick_skill" => 40,
          "skill_xp" => 1,
          "xp" => [5, 12]
        },
        "jail" => %{
          "ticks" => [3, 10],
          "bribe_cost" => [30, 60],
          "escape_chance" => 0.25,
          "confiscation_chance" => 0.5,
          "escape_hp_loss" => [10, 25],
          "jail_feed" => [2, 6]
        },
        "pets" => %{
          "hunger_per_tick" => 0.6,
          "loyalty_decay" => 0.4,
          "loyalty_zero_leave" => true,
          "revive_hours" => 4,
          "feed_cost" => 8,
          "feed_loyalty" => 6,
          "play_mood" => 12,
          "train_loyalty" => 4,
          "adopt_chance" => 0.08,
          "wolf_help" => 0.3,
          "owl_discovery" => 0.25,
          "cat_mood" => 2
        }
      },
      "law" => %{
        "reputation" => %{
          "quest_complete" => 5,
          "monster_kill" => 1,
          "crime" => 10,
          "fine_paid" => 2
        },
        "factions_by_region" => %{
          "Вайтран" => "Империя",
          "Рифтен" => "Империя",
          "Солитьюд" => "Империя",
          "Виндхельм" => "Братья Бури",
          "Морфал" => "Братья Бури",
          "Фолкрит" => "Империя",
          "Данстар" => "Братья Бури",
          "Маркарт" => "Империя",
          "Винтерхолд" => "Независимые"
        },
        "default_faction" => "Империя"
      },
      "world_kernel" => %{
        "tick_ms" => 60_000,
        "event_pool" => [
          %{
            "type" => "fair",
            "name" => "Ярмарка",
            "desc" => "Торговцы съехались: цены ниже на 20%",
            "ttl" => 24,
            "where" => "city"
          },
          %{
            "type" => "monster_wave",
            "name" => "Волна монстров",
            "desc" => "Из пустошей идёт нечисть",
            "ttl" => 12,
            "where" => "wilderness"
          },
          %{
            "type" => "dragon",
            "name" => "Дракон",
            "desc" => "Над землёй кружит тень дракона",
            "ttl" => 48,
            "where" => "any"
          },
          %{
            "type" => "eclipse",
            "name" => "Затмение",
            "desc" => "Солнце скрыто — тени длиннее",
            "ttl" => 6,
            "where" => "any"
          }
        ]
      },
      "world_limits" => %{
        "utility_cap" => 0.15,
        "price_min" => 0.6,
        "price_max" => 1.8,
        "encounter_cap" => 0.3
      },
      # C-1 «Часовня Девули»: коммунальная стройка — единый источник правды в модуле
      "construction" => TesIdle.World.Construction.default_config(),
      # Гильдии (G-0/G-1): каркас + экономика подношений — параметры только в конфигах
      "guild" => %{
        "create_cost" => 500,
        "rename_cost" => 100,
        "emblem_cost" => 50,
        "exp_per_gold" => 1,
        "points_per_gold" => 0.1,
        "daily_points_cap" => 150,
        "points_per_kill" => 1,
        "daily_activity_cap" => 30,
        "level_exp_base" => 1000,
        "level_exp_growth" => 1.4,
        "max_level" => 20,
        "buffs_per_level" => %{"xp_mult" => 0.02, "attack_flat" => 1, "hp_flat" => 10},
        "chat_rate_limit_sec" => 2,
        "chat_max_len" => 200,
        "rejoin_cooldown_hours" => 12
      },
      # Гильдии (G-3): лавка — цены в очках, предметы ищутся по имени (seed_guild_shop)
      # CD-1: fallback-каталог = зеркало сида (12 позиций); в БД настоящий каталог.
      "guild_shop" => %{
        "catalog" => [
          %{"name" => "Плащ Соратников", "points" => 60},
          %{"name" => "Знак гильдии", "points" => 40},
          %{"name" => "Эликсир Соборности", "points" => 20},
          %{"name" => "Шлем дозорного знамени", "points" => 70},
          %{"name" => "Сапоги тысяч вёрст", "points" => 45},
          %{"name" => "Кольцо общего дела", "points" => 90},
          %{"name" => "Перчатки печатника", "points" => 30},
          %{"name" => "Сталь основателя", "points" => 180},
          %{"name" => "Реликвия казначея", "points" => 100},
          %{"name" => "Броня смотрителя алтаря", "points" => 150},
          %{"name" => "Искра", "points" => 50},
          %{"name" => "Медовуха сплочения", "points" => 25},
          %{"name" => "Похлёбка казармы", "points" => 15}
        ]
      },
      # C-2 «Небесная кузня»: заточка экипировки — цена round(base × level^growth), кап уровней
      "skyforge" => %{"base_cost" => 50, "growth" => 1.8, "cap" => 10, "fail_chance" => 0}
    }

    Enum.reduce(db_configs, defaults, fn {key, value_json}, acc ->
      case Jason.decode(value_json) do
        {:ok, value} -> Map.put(acc, key, value)
        _ -> acc
      end
    end)
  end

  defp parse_state_data(nil), do: %{}

  defp parse_state_data(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end

  defp parse_state_data(_), do: %{}
end

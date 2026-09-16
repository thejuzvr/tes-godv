defmodule TesIdle.Game.Actions.FightAction do
  @moduledoc "Hero fights a monster — multi-tick combat with state_data.combat."
  @behaviour TesIdle.Game.Action

  alias TesIdle.Repo
  alias TesIdle.Game.{GameContext, Pets}
  alias TesIdle.Schemas.Monster
  import Ecto.Query

  @impl true
  def score(%GameContext{} = ctx) do
    # If already in combat, always fight
    if fighting?(ctx), do: 1000, else: base_score(ctx)
  end

  @impl true
  def execute(%GameContext{} = ctx) do
    state_data = decode_state_data(ctx.hero)

    if state_data["combat"] do
      # Continue existing combat — process one round
      process_combat_round(ctx, state_data)
    else
      # Start new combat
      start_new_combat(ctx)
    end
  end

  defp start_new_combat(%GameContext{} = ctx) do
    level_range = get_in(ctx.configs, ["combat", "level_range"]) || 2
    damage_variance = get_in(ctx.configs, ["combat", "damage_variance"]) || [-3, 5]

    monster =
      if ctx.hero.location_id == nil do
        # Локация может быть unset в тестовых сценариях — честный «врагов нет»
        nil
      else
        Repo.one(
          from m in Monster,
            where: m.location_id == ^ctx.hero.location_id
              and m.min_level <= ^(ctx.hero.level + level_range)
              and m.is_active == true,
            order_by: fragment("RANDOM()"),
            limit: 1
        )
      end

    if monster do
      scale = 1 + ctx.hero.level * 0.03
      scaled_hp = trunc(monster.hp * scale)
      scaled_attack_min = trunc(monster.attack_min * (1 + ctx.hero.level * 0.02))
      scaled_attack_max = trunc(monster.attack_max * (1 + ctx.hero.level * 0.02))
      scaled_defense = trunc(monster.defense * (1 + ctx.hero.level * 0.01))

      {weapon_bonus, armor_bonus} = get_equipment_bonuses(ctx.equipment)
      # G-1: баф гильдии — плоская прибавка к атаке и «свежие силы» (HP) на бой
      buff = Map.get(ctx, :guild_buff) || %{}
      guild_attack = (buff["attack_flat"] || 0) |> trunc()
      guild_hp = (buff["hp_flat"] || 0) |> trunc()

      effective_attack = ctx.hero.attack + weapon_bonus + guild_attack
      effective_attack = if ctx.hero.sp <= 0, do: trunc(effective_attack * 0.8), else: effective_attack
      effective_defense = ctx.hero.defense + armor_bonus

      combat = %{
        "monster_id" => to_string(monster.id),
        "monster_name" => monster.name,
        "monster_icon" => "👹",
        "monster_hp" => scaled_hp,
        "monster_max_hp" => scaled_hp,
        "monster_attack_min" => scaled_attack_min,
        "monster_attack_max" => scaled_attack_max,
        "monster_defense" => scaled_defense,
        "monster_xp_reward" => trunc(monster.xp_reward * scale),
        "monster_gold_min" => trunc(monster.gold_min * scale),
        "monster_gold_max" => trunc(monster.gold_max * scale),
        "hero_hp" => ctx.hero.hp + guild_hp,
        "hero_max_hp" => ctx.hero.max_hp + guild_hp,
        "effective_attack" => effective_attack,
        "effective_defense" => effective_defense,
        "damage_variance" => damage_variance,
        "total_hero_damage" => 0,
        "total_monster_damage" => 0,
        "rounds_left" => 20,
      }

      {:ok, %{
        state_to: "fighting",
        combat_start: combat,
        state_data_update: %{"combat" => combat},
      }}
    else
      {:ok, %{state_to: "exploring"}}
    end
  end

  defp process_combat_round(%GameContext{} = ctx, state_data) do
    combat = state_data["combat"]
    rounds_left = combat["rounds_left"]

    if rounds_left <= 0 do
      resolve_combat(ctx, combat, "max_rounds")
    else
      # Hero attacks (волк может помочь — шанс по лояльности)
      variance = combat["damage_variance"] || [-3, 5]
      {wolf_bonus, wolf_name} = wolf_help(ctx)
      hero_dmg = max(1, combat["effective_attack"] + Enum.random(variance) - combat["monster_defense"]) + wolf_bonus
      new_monster_hp = combat["monster_hp"] - hero_dmg
      new_hero_dmg = combat["total_hero_damage"] + hero_dmg

      if new_monster_hp <= 0 do
        # Monster defeated
        resolve_combat(ctx, %{combat | "monster_hp" => 0, "total_hero_damage" => new_hero_dmg, "rounds_left" => rounds_left - 1}, "victory")
      else
        # Monster attacks
        monster_dmg = max(1, Enum.random(combat["monster_attack_min"]..combat["monster_attack_max"]) + Enum.random(variance) - combat["effective_defense"])
        new_hero_hp = combat["hero_hp"] - monster_dmg
        new_monster_dmg = combat["total_monster_damage"] + monster_dmg

        updated_combat = %{combat |
          "monster_hp" => new_monster_hp,
          "hero_hp" => new_hero_hp,
          "total_hero_damage" => new_hero_dmg,
          "total_monster_damage" => new_monster_dmg,
          "rounds_left" => rounds_left - 1,
        }

        if new_hero_hp <= 0 do
          # Hero defeated
          resolve_combat(ctx, updated_combat, "defeat")
        else
          # Continue fighting next tick
          progress = %{
            hero_hp: new_hero_hp,
            hero_max_hp: combat["hero_max_hp"],
            monster_hp: new_monster_hp,
            monster_max_hp: combat["monster_max_hp"],
            monster_name: combat["monster_name"],
            monster_icon: combat["monster_icon"],
            round: 20 - rounds_left + 1,
            max_rounds: 20,
          }

          progress = if wolf_name, do: Map.put(progress, :wolf_help, wolf_name), else: progress

          {:ok, %{
            state_to: "fighting",
            state_data_update: %{"combat" => updated_combat},
            combat_progress: progress,
          }}
        end
      end
    end
  end

  defp resolve_combat(ctx, combat, reason) do
    # Combat завершён: дельта-формат state_data_update ("combat" => nil),
    # НЕ весь state_data — иначе merge затирал advance_plan и decision_log
    case reason do
      "victory" ->
        xp = combat["monster_xp_reward"] || 0
        gold = Enum.random(combat["monster_gold_min"]..max(combat["monster_gold_min"], combat["monster_gold_max"]))

        # W-5: охота героев разрежает локацию (агрегатор → Kernel, √-масштаб)
        if ctx.hero.location_id, do: TesIdle.World.Aggregator.kill(ctx.hero.location_id)

        # Roll for loot drops from MonsterLoot table
        items_looted = roll_loot(combat["monster_template_id"], ctx.hero.id)

        result = %{
          state_to: "exploring",
          combat_result: %{
            monster_name: combat["monster_name"],
            victory: true,
            hero_defeated: false,
            rounds: (combat["rounds_left"] || 0),
            total_hero_damage: combat["total_hero_damage"],
            total_monster_damage: combat["total_monster_damage"],
            xp: xp,
            gold: gold,
          },
          xp: xp,
          gold_change: gold,
          hp_change: -combat["total_monster_damage"],
          state_data_update: %{"combat" => nil},
        }

        result = if items_looted != [] do
          _loot_text = items_looted |> Enum.join("\n")
          Map.put(result, :loot_items, items_looted)
        else
          result
        end

        {:ok, result}

      "defeat" ->
        # Питомец прикрывает отход: шанс погибнуть (cooldown + revive_at)
        pet_death_note = maybe_pet_sacrifice(ctx)

        {:ok, %{
          state_to: "dead",
          combat_result: %{
            monster_name: combat["monster_name"],
            victory: false,
            hero_defeated: true,
            rounds: (combat["rounds_left"] || 0),
            total_hero_damage: combat["total_hero_damage"],
            total_monster_damage: combat["total_monster_damage"],
            xp: 0,
            gold: 0,
            pet_death: pet_death_note,
          },
          state_data_update: %{"combat" => nil},
        }}

      "max_rounds" ->
        # Both still alive — end combat, partial rewards
        xp = trunc((combat["monster_xp_reward"] || 0) * 0.3)
        {:ok, %{
          state_to: "exploring",
          combat_result: %{
            monster_name: combat["monster_name"],
            victory: false,
            hero_defeated: false,
            rounds: 20,
            total_hero_damage: combat["total_hero_damage"],
            total_monster_damage: combat["total_monster_damage"],
            xp: xp,
            gold: 0,
          },
          xp: xp,
          hp_change: -combat["total_monster_damage"],
          state_data_update: %{"combat" => nil},
        }}
    end
  end

  defp fighting?(ctx) do
    state_data = decode_state_data(ctx.hero)
    ctx.hero.state == "fighting" || state_data["combat"] != nil
  end

  defp decode_state_data(hero) do
    case Jason.decode(hero.state_data || "{}") do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end

  # Волк помогает в бою: бонусный урон по шансу от лояльности
  defp wolf_help(ctx) do
    cfg = ((ctx.configs || %{})["activities"] || %{})["pets"] || %{}
    pet = Pets.active(ctx.hero.id)

    if Pets.wolf_fight_help?(pet, cfg) do
      {Enum.random(3..8), pet.name}
    else
      {0, nil}
    end
  end

  # Питомец прикрывает отход при поражении: 30% погибнуть (cooldown)
  defp maybe_pet_sacrifice(ctx) do
    pet = Pets.active(ctx.hero.id)

    if pet && :rand.uniform() < 0.3 do
      cfg = ((ctx.configs || %{})["activities"] || %{})["pets"] || %{}
      revive_at = Pets.on_combat_death(pet, cfg)

      "pet_down:#{pet.name}:#{DateTime.to_iso8601(revive_at)}"
    else
      nil
    end
  end

  defp base_score(%GameContext{} = ctx) do
    base = location_weight(ctx.location_type, :fighting)
    base = if ctx.needs.fatigue > 70, do: base - 10, else: base
    base = if ctx.hero.hp < ctx.hero.max_hp * 0.3, do: base - 20, else: base
    base = cond do
      ctx.hour >= 12 and ctx.hour < 18 -> base + 10
      ctx.hour >= 22 or ctx.hour < 6 -> base - 10
      true -> base
    end
    if quest_boost?(ctx.active_quest, :kill), do: base + 80, else: base
  end

  defp get_equipment_bonuses(nil), do: {0, 0}
  defp get_equipment_bonuses(equipment) do
    alias TesIdle.Schemas.Item

    # C-2 кузня: уровни заточки надетых предметов (+1 attack/defense за уровень)
    forge_bonus = TesIdle.Game.Skyforge.equipment_bonus(equipment)

    slots = [:weapon_id, :head_id, :body_id, :legs_id, :ring_id, :amulet_id]
    {base_atk, base_def} =
      Enum.reduce(slots, {0, 0}, fn slot, {atk, def} ->
        item_id = Map.get(equipment, slot)
        if item_id do
          item = Repo.get(Item, item_id)
          if item, do: {atk + (item.attack_bonus || 0), def + (item.defense_bonus || 0)}, else: {atk, def}
        else
          {atk, def}
        end
      end)

    {base_atk + elem(forge_bonus, 0), base_def + elem(forge_bonus, 1)}
  end

  defp location_weight("dungeon", :fighting), do: 45
  defp location_weight("wilderness", :fighting), do: 30
  defp location_weight("city", :fighting), do: 10
  defp location_weight("village", :fighting), do: 20
  defp location_weight(_, :fighting), do: 15

  defp quest_boost?(nil, _), do: false
  defp quest_boost?(active_quest, :kill) do
    import Ecto.Query
    step = Repo.one(
      from s in TesIdle.Schemas.QuestStep,
        where: s.quest_id == ^active_quest.quest_id and s.step_order == ^active_quest.current_step,
        limit: 1
    )
    step != nil and step.step_type == "kill"
  end

  defp roll_loot(nil, _hero_id), do: []
  defp roll_loot(monster_template_id, hero_id) do
    alias TesIdle.Schemas.{MonsterLoot, Item, InventoryItem}

    # convert string UUID to binary if needed
    monster_uuid = if is_binary(monster_template_id) and byte_size(monster_template_id) == 36 do
      Ecto.UUID.cast!(monster_template_id)
    else
      monster_template_id
    end

    loot_entries = Repo.all(
      from ml in MonsterLoot,
        where: ml.monster_id == ^monster_uuid,
        preload: [:item]
    )

    loot_entries
    |> Enum.filter(fn ml -> :rand.uniform() <= (ml.drop_chance || 0.3) end)
    |> Enum.map(fn ml ->
      if ml.item do
        # Add to inventory or increment quantity
        existing = Repo.one(
          from ii in InventoryItem,
            where: ii.hero_id == ^hero_id and ii.item_id == ^ml.item.id
        )
        if existing do
          existing |> Ecto.Changeset.change(%{quantity: existing.quantity + 1}) |> Repo.update!()
        else
          Repo.insert!(%InventoryItem{hero_id: hero_id, item_id: ml.item.id, quantity: 1})
        end
        ml.item.name
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end

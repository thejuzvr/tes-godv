defmodule TesIdle.Game.Narrative.NarrativeContext do
  alias TesIdle.Game.Brain.Genome

  @moduledoc """
  Describes the complete state of the world at narrative generation time.
  Does NOT make decisions — only provides data for the Director.
  """

  defstruct [
    :hero,
    :location,
    :location_type,
    :weather,
    :configs,
    :game_hour,
    :daytime,
    :mood,
    :hero_state,
    :travel,
    :combat,
    :quest,
    :personality,
    :memories,
    :quirks,
    :inventory_count,
    :equipment_slots,
    :action_context,
    tags: []
  ]

  @type t :: %__MODULE__{
          hero: map(),
          location: map() | nil,
          location_type: String.t(),
          weather: String.t(),
          configs: map(),
          game_hour: float(),
          daytime: String.t(),
          mood: float(),
          hero_state: String.t(),
          travel: map() | nil,
          combat: map() | nil,
          quest: map() | nil,
          personality: map(),
          memories: list(),
          quirks: list(atom()),
          inventory_count: integer(),
          equipment_slots: integer(),
          tags: list(String.t())
        }

  @doc "Build context from GameContext + result."
  def build(ctx, result) do
    tags = build_tags(ctx, result)

    %__MODULE__{
      hero: ctx.hero,
      location: ctx.location,
      location_type: ctx.location_type,
      # Погода ядра мира — ключ ("clear"/"rain"/...); легаси location.weather не читаем
      weather: ctx.weather || "clear",
      # configs (game_configs) — нужен Composer (N-2) для весов сцен
      configs: ctx.configs || %{},
      game_hour: ctx.hero.game_hour,
      daytime: daytime(ctx.hero.game_hour),
      mood: ctx.hero.mood,
      hero_state: ctx.hero.state,
      travel: ctx.travel_state,
      combat: ctx.combat_state,
      quest: ctx.active_quest,
      personality: ctx.personality,
      memories: ctx.memories,
      # Причуды BrainHash (0..2 атомов) — источник персонажных closer'ов (N-3)
      quirks: quirks(ctx.hero),
      inventory_count: length(ctx.inventory),
      equipment_slots: count_equipment(ctx.equipment),
      action_context: result[:context] || %{},
      tags: tags
    }
  end

  # Private helpers

  defp quirks(%{brain_hash: hash}) when is_binary(hash) and byte_size(hash) == 64 do
    case Base.decode16(hash, case: :mixed) do
      {:ok, _} -> Map.get(Genome.derive(hash), :quirks, [])
      :error -> []
    end
  end

  defp quirks(_), do: []

  defp count_equipment(nil), do: 0

  defp count_equipment(equip) do
    [:weapon_id, :head_id, :body_id, :legs_id, :ring_id, :amulet_id]
    |> Enum.count(&(Map.get(equip, &1) != nil))
  end

  defp daytime(hour) do
    cond do
      hour >= 6 and hour < 12 -> "morning"
      hour >= 12 and hour < 18 -> "afternoon"
      hour >= 18 and hour < 22 -> "evening"
      true -> "night"
    end
  end

  defp build_tags(ctx, result) do
    dt = daytime(ctx.hero.game_hour)
    personality = ctx.personality || %{}

    []
    |> add_tag(result[:state_to] == "fighting", "combat")
    |> add_tag(result[:state_to] == "traveling", "travel")
    |> add_tag(result[:state_to] == "resting", "peace")
    |> add_tag(ctx.combat_state != nil, "combat")
    |> add_tag(ctx.travel_state != nil, "travel")
    |> add_tag(ctx.location_type == "dungeon", "dungeon")
    |> add_tag(ctx.location_type == "wilderness", "wilderness")
    |> add_tag(ctx.location_type == "city", "city")
    |> add_tag(ctx.location_type == "village", "village")
    |> add_tag(ctx.location_type in ["wilderness", "dungeon"], "danger")
    |> add_tag(ctx.location_type in ["village", "city"], "safe")
    |> add_tag(ctx.hero.hp < ctx.hero.max_hp * 0.5, "injured")
    |> add_tag(ctx.hero.hp >= ctx.hero.max_hp * 0.7, "healthy")
    |> add_tag(ctx.hero.hunger > 70, "hungry")
    |> add_tag(ctx.hero.fatigue > 70, "fatigued")
    |> add_tag(ctx.mood < 35, "depressed")
    |> add_tag(ctx.mood > 65, "excited")
    |> add_tag(dt in ["night", "dawn"], "night")
    |> add_tag(dt in ["morning", "afternoon"], "day")
    |> add_tag(dt == "evening", "evening")
    # Фаза 3: погода — ключи ядра мира (ctx.weather), НЕ легаси location.weather
    # (заморожен в «Ясно» в БД — rain/snow/fog теги никогда не срабатывали)
    |> add_tag(get_weather(ctx) in ["rain", "storm"], "rain")
    |> add_tag(get_weather(ctx) == "snow", "snow")
    |> add_tag(get_weather(ctx) == "fog", "fog")
    |> add_tag(get_weather(ctx) in ["clear", "cloud"], "clear")
    |> add_tag(ctx.location && ctx.location.has_inn, "inn")
    |> add_tag(ctx.location && ctx.location.has_shop, "merchant")
    |> add_tag(ctx.combat_state != nil, "combat")
    |> add_tag(ctx.travel_state != nil, "travel")
    |> add_tag(map_size(personality) > 0 && Map.get(personality, :bravery, 50) > 60, "brave")
    |> add_tag(map_size(personality) > 0 && Map.get(personality, :caution, 50) > 60, "cautious")
    |> add_tag(map_size(personality) > 0 && Map.get(personality, :curiosity, 50) > 60, "curious")
    |> add_tag(result[:combat_result] && result[:combat_result][:victory], "victory")
    |> add_tag(result[:combat_result] && !result[:combat_result][:victory], "defeat")
    # Полировка (аудит Хроники): «послесловие боя» — предыдущий тик ПОРАЖЕНИЕ,
    # текущий тик уже без combat_result (бой завершён, combat-тег снят). Даёт
    # remember_defeat шанс сработать: сейчас событие недостижимо, потому что
    # defeat существует только внутри боевого тика вместе с combat.
    |> add_tag(aftermath_defeat?(ctx, result), "aftermath")
    |> add_tag(result[:gold_change] && result[:gold_change] > 0, "loot")
    |> add_tag(result[:gold_change] && result[:gold_change] < 0, "spent")
    # Фаза 3 (аудит D): shopping/looting не имели тегов → падали в generic_action,
    # хотя шаблоны shop в БД есть. Добавляем состояния покупки и сна.
    |> add_tag(result[:state_to] == "shopping", "shopping")
    |> add_tag(result[:state_to] == "looting", "looting")
    |> add_tag(result[:state_to] == "resting", "sleep")
    |> add_tag(ctx.location && ctx.location.location_type == "village", "village")
    # Полировка (аудит Хроники): тег берём из result.state_to (состояние ПОСЛЕ
    # тика, то же, что видит NarrativeDirector через requires), а не из
    # ctx.hero.state (снапшот ДО тика — socializing почти никогда не был true).
    |> add_tag(result[:state_to] == "socializing", "socializing")
    |> add_tag(result[:state_to] == "resting", "resting")
    |> add_tag(result[:state_to] == "fishing", "fishing")
    |> add_tag(result[:state_to] == "gathering", "gathering")
    |> add_tag(result[:state_to] == "mining", "mining")
    |> add_tag(get_in(result, [:context, "mining_phase"]) == "start", "mining_start")
    |> add_tag(get_in(result, [:context, "mining_phase"]) == "wait", "mining_work")
    |> add_tag(get_in(result, [:context, "mining_phase"]) == "found", "mining_yield")
    |> add_tag(result[:state_to] == "sneaking", "sneaking")
    |> add_tag(result[:state_to] == "breaking_in", "breaking_in")
    |> add_tag(result[:state_to] == "jailed", "jailed")
    |> add_tag(result[:state_to] == "pet_care", "pet_care")
    |> add_tag(ctx.location_type in ["wilderness"], "road")
    |> add_tag(ctx.location_type == "dungeon", "ruins")
    |> add_tag(ctx.location_type == "wilderness", "forest")
    |> add_tag(ctx.location_type in ["village", "city"], "road")
    |> add_tag(ctx.location && ctx.location.has_inn, "indoors")
    |> add_tag(ctx.location && !ctx.location.has_inn, "outdoors")
    |> add_tag(ctx.combat_state != nil, "danger")
    |> add_tag(ctx.combat_state == nil, "peace")
    |> add_nearby_tags(ctx)
    |> add_tag(ctx.mood < 35, "depressed")
    |> add_tag(ctx.mood > 65, "excited")
    |> Enum.uniq()
  end

  defp add_tag(tags, false, _), do: tags
  defp add_tag(tags, nil, _), do: tags
  defp add_tag(tags, true, tag), do: [tag | tags]

  defp get_weather(ctx), do: ctx.weather || "clear"

  # «Послесловие поражения»: в памяти героя (state_data["memories"]) свежая
  # запись defeat, а текущий тик мирный (combat_result nil → combat-тега нет).
  defp aftermath_defeat?(ctx, result) do
    result[:combat_result] == nil and
      ctx.memories != nil and
      Enum.any?(Enum.take(ctx.memories, -2), &(&1["type"] == "defeat"))
  end

  defp add_nearby_tags(tags, ctx) do
    if ctx.location && ctx.location.location_type in ["wilderness", "dungeon"] do
      alias TesIdle.Repo
      alias TesIdle.Schemas.Monster
      import Ecto.Query

      count =
        Repo.one(
          from m in Monster,
            where: m.location_id == ^ctx.location.id and m.is_active == true,
            select: count()
        )

      tags
      |> add_tag(count && count > 0, "monsters_nearby")
      |> add_tag(count && count >= 3, "dangerous")
      |> add_tag(ctx.location.name == "Драконья Падь", "dragon")
    else
      tags
    end
  end
end

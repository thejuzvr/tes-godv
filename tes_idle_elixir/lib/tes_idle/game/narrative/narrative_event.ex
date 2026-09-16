defmodule TesIdle.Game.Narrative.NarrativeEvent do
  @moduledoc """
  Narrative events that can occur in the world.
  Each event has: name, required_tags, forbidden_tags, weight, chains (next possible events).
  """

  defstruct [:name, :requires, :forbids, :weight, :chains]

  @type t :: %__MODULE__{
    name: String.t(),
    requires: [String.t()],
    forbids: [String.t()],
    weight: integer(),
    chains: [String.t()]
  }

  @doc "All available narrative events."
  def all do
    [
      # --- Travel events ---
      %__MODULE__{name: "leave_city", requires: ["city", "travel"], forbids: [], weight: 5, chains: ["travel_road"]},
      %__MODULE__{name: "travel_road", requires: ["travel", "day"], forbids: ["city"], weight: 30, chains: ["meet_merchant", "spot_bandits", "travel_shortcut", "bad_weather"]},
      %__MODULE__{name: "travel_shortcut", requires: ["travel", "wilderness"], forbids: [], weight: 10, chains: ["hear_wolves", "discover_ruin", "find_shrine"]},
      %__MODULE__{name: "cross_bridge", requires: ["travel", "village", "day"], forbids: [], weight: 8, chains: ["travel_road"]},
      %__MODULE__{name: "enter_city", requires: ["travel", "city"], forbids: [], weight: 5, chains: ["meet_merchant"]},

      # --- Discovery events ---
      %__MODULE__{name: "discover_ruin", requires: ["wilderness", "day", "curious"], forbids: ["city"], weight: 10, chains: ["notice_tracks"]},
      %__MODULE__{name: "discover_cave", requires: ["wilderness", "dungeon"], forbids: ["city"], weight: 15, chains: ["hear_wolves"]},
      %__MODULE__{name: "find_shrine", requires: ["wilderness", "day"], forbids: [], weight: 8, chains: ["watch_sunset"]},
      %__MODULE__{name: "find_abandoned_cart", requires: ["travel", "day"], forbids: ["city"], weight: 12, chains: ["notice_tracks"]},
      %__MODULE__{name: "notice_tracks", requires: ["wilderness", "curious"], forbids: [], weight: 15, chains: ["spot_bandits", "hear_wolves"]},

      # --- Combat events ---
      %__MODULE__{name: "enemy_ambush", requires: ["danger", "travel"], forbids: ["city"], weight: 20, chains: ["hero_victory", "hero_defeat"]},
      %__MODULE__{name: "spot_bandits", requires: ["danger", "road", "day"], forbids: ["city"], weight: 10, chains: ["enemy_ambush"]},
      %__MODULE__{name: "hear_wolves", requires: ["night", "wilderness"], forbids: ["city"], weight: 15, chains: ["enemy_ambush"]},
      %__MODULE__{name: "hero_victory", requires: ["combat", "victory"], forbids: [], weight: 50, chains: ["find_loot"]},
      %__MODULE__{name: "hero_defeat", requires: ["combat", "defeat"], forbids: [], weight: 30, chains: []},

      # --- Rest events ---
      %__MODULE__{name: "sleep_in_inn", requires: ["inn", "night", "resting"], forbids: [], weight: 25, chains: ["travel_road"]},
      %__MODULE__{name: "rest_by_fire", requires: ["night", "wilderness", "resting"], forbids: ["inn"], weight: 20, chains: ["hear_wolves"]},
      %__MODULE__{name: "watch_sunset", requires: ["evening", "peace"], forbids: ["combat"], weight: 5, chains: []},

      # --- Social events ---
      %__MODULE__{name: "meet_merchant", requires: ["travel", "day", "merchant"], forbids: [], weight: 15, chains: ["travel_road"]},
      %__MODULE__{name: "learn_rumors", requires: ["inn", "socializing"], forbids: [], weight: 20, chains: ["find_shrine"]},
      %__MODULE__{name: "hear_song", requires: ["inn", "evening", "socializing"], forbids: [], weight: 10, chains: []},

      # --- Weather events ---
      %__MODULE__{name: "bad_weather", requires: ["travel", "rain"], forbids: [], weight: 8, chains: ["travel_road"]},
      %__MODULE__{name: "shelter_from_storm", requires: ["rain", "inn"], forbids: [], weight: 10, chains: ["learn_rumors"]},

      # --- Finding loot events ---
      %__MODULE__{name: "find_loot", requires: ["loot"], forbids: [], weight: 30, chains: ["travel_road"]},
      %__MODULE__{name: "discover_treasure", requires: ["dungeon", "victory"], forbids: [], weight: 20, chains: ["travel_road"]},

      # --- Exploration events ---
      %__MODULE__{name: "hear_river", requires: ["wilderness", "day"], forbids: [], weight: 15, chains: ["cross_bridge"]},
      %__MODULE__{name: "find_tracks", requires: ["wilderness", "curious"], forbids: [], weight: 12, chains: ["spot_bandits"]},
      %__MODULE__{name: "hear_birds", requires: ["wilderness", "day"], forbids: ["night"], weight: 25, chains: []},
      %__MODULE__{name: "smell_flowers", requires: ["village", "day", "peace"], forbids: ["combat"], weight: 8, chains: []},

      # --- Memory + personality events ---
      # Полировка: remember_defeat был недостижим (defeat-тег существует только
      # в боевом тике, где forbids combat отсекает событие). aftermath-тег
      # ставится в мирный тик сразу после поражения (см. narrative_context).
      %__MODULE__{name: "remember_defeat", requires: ["aftermath"], forbids: [], weight: 25, chains: ["rest_by_fire"]},
      %__MODULE__{name: "feel_confident", requires: ["victory"], forbids: ["defeat"], weight: 12, chains: ["search_danger"]},
      %__MODULE__{name: "avoid_danger", requires: ["dangerous", "cautious"], forbids: ["brave"], weight: 10, chains: ["hear_wolves"]},
      %__MODULE__{name: "search_danger", requires: ["monsters_nearby", "brave"], forbids: ["cautious"], weight: 15, chains: ["enemy_ambush"]},
      %__MODULE__{name: "collect_herbs", requires: ["forest", "day"], forbids: ["night"], weight: 10, chains: []},

      # --- Phase 2: activities (fishing / gathering / crime / pets) ---
      %__MODULE__{name: "fishing_catch", requires: ["fishing"], forbids: [], weight: 40, chains: []},
      %__MODULE__{name: "fishing_wait", requires: ["fishing"], forbids: [], weight: 25, chains: []},
      %__MODULE__{name: "gather_plants", requires: ["gathering"], forbids: [], weight: 40, chains: []},
      %__MODULE__{name: "steal_clean", requires: ["sneaking"], forbids: [], weight: 30, chains: []},
      %__MODULE__{name: "steal_spotted", requires: ["sneaking"], forbids: [], weight: 25, chains: []},
      %__MODULE__{name: "break_in_ok", requires: ["breaking_in"], forbids: [], weight: 30, chains: []},
      %__MODULE__{name: "break_in_trap", requires: ["breaking_in"], forbids: [], weight: 25, chains: []},
      %__MODULE__{name: "jail_time", requires: ["jailed"], forbids: [], weight: 40, chains: []},
      %__MODULE__{name: "pet_care_moment", requires: ["pet_care"], forbids: [], weight: 45, chains: []},

      # --- Фаза 3 (аудит D): shopping/looting состояния не имели событий —
      # покупки и сбор добычи падали в generic_action.
      # Имена событий = template_type в БД: shop/loot (есть в сиде).
      %__MODULE__{name: "shop", requires: ["shopping"], forbids: [], weight: 40, chains: []},
      %__MODULE__{name: "loot", requires: ["looting"], forbids: [], weight: 40, chains: []},
      %__MODULE__{name: "sleep_in_inn", requires: ["inn", "night", "resting"], forbids: [], weight: 25, chains: ["travel_road"]},

      # --- Generic fallback ---
      %__MODULE__{name: "generic_action", requires: [], forbids: [], weight: 1, chains: []},
    ]
  end
end

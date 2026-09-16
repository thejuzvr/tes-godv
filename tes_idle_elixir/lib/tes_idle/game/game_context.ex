defmodule TesIdle.Game.GameContext do
  @moduledoc """
  Data struct that holds all context needed for a single game tick.
  Built by ContextBuilder, consumed by DecisionMaker and Actions.
  """

  defstruct [
    :hero,
    :location,
    :configs,
    :inventory,
    :equipment,
    :active_quest,
    :hour,
    :location_type,
    :mood,
    :needs,
    :combat_state,
    :travel_state,
    :equip_events,
    :personality,
    :plan,
    :memories,
    :state_data,
    :weather,
    :world,
    :guild_buff,
  ]

  @type t :: %__MODULE__{
    hero: map(),
    location: map() | nil,
    configs: map(),
    inventory: list(),
    equipment: map() | nil,
    active_quest: map() | nil,
    hour: float(),
    location_type: String.t(),
    mood: float(),
    needs: %{hunger: float(), fatigue: float(), morale: float()},
    combat_state: map() | nil,
    travel_state: map() | nil,
    equip_events: list(),
    personality: map(),
    plan: list(),
    memories: list(),
    state_data: map(),
    weather: String.t(),
    world: map() | nil,
    # G-1: баф гильдии %{level, xp_mult, attack_flat, hp_flat} | nil
    guild_buff: map() | nil,
  }
end

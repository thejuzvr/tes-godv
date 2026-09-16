defmodule TesIdle.Game.Memory do
  @moduledoc """
  Hero emotional memory system.
  Tracks victories, defeats, discoveries, social encounters.
  Memories influence utility scores and narrative generation.
  """

  alias TesIdle.Repo
  alias TesIdle.Schemas.Hero

  @max_memories 20

  @doc "Get all memories from hero state_data."
  def get_memories(hero) do
    state_data = decode(hero.state_data)
    Map.get(state_data, "memories", [])
  end

  @doc "Add a victory memory."
  def add_victory(hero, monster_name, gold_earned) do
    memory = %{
      "type" => "victory",
      "monster" => monster_name,
      "day" => hero.game_day,
      "gold_earned" => gold_earned,
      "mood_impact" => 10,
    }
    append(hero, memory)
  end

  @doc "Add a defeat memory."
  def add_defeat(hero, monster_name, gold_lost) do
    memory = %{
      "type" => "defeat",
      "monster" => monster_name,
      "day" => hero.game_day,
      "gold_lost" => gold_lost,
      "mood_impact" => -20,
    }
    append(hero, memory)
  end

  @doc "Add a discovery memory."
  def add_discovery(hero, what) do
    memory = %{
      "type" => "discovery",
      "what" => what,
      "day" => hero.game_day,
      "mood_impact" => 15,
    }
    append(hero, memory)
  end

  @doc "Add a social memory."
  def add_social(hero, npc_name) do
    memory = %{
      "type" => "social",
      "npc" => npc_name,
      "day" => hero.game_day,
      "mood_impact" => 8,
    }
    append(hero, memory)
  end

  @doc "Add a shop memory."
  def add_shop(hero, item_name, gold_spent) do
    memory = %{
      "type" => "shop",
      "item" => item_name,
      "day" => hero.game_day,
      "gold_spent" => gold_spent,
      "mood_impact" => 5,
    }
    append(hero, memory)
  end

  @doc "Add a travel memory."
  def add_travel(hero, destination) do
    memory = %{
      "type" => "travel",
      "destination" => destination,
      "day" => hero.game_day,
      "mood_impact" => 3,
    }
    append(hero, memory)
  end

  @doc "Add a quest completion memory."
  def add_quest_complete(hero, quest_name) do
    memory = %{
      "type" => "quest_complete",
      "quest" => quest_name,
      "day" => hero.game_day,
      "mood_impact" => 20,
    }
    append(hero, memory)
  end

  @doc "Fight memory modifier for utility scoring."
  def fight_modifier(hero) do
    memories = get_memories(hero)
    defeats = Enum.count(memories, &(&1["type"] == "defeat"))
    victories = Enum.count(memories, &(&1["type"] == "victory"))
    (victories - defeats) * 2
  end

  @doc "Explore memory modifier for utility scoring."
  def explore_modifier(hero) do
    memories = get_memories(hero)
    discoveries = Enum.count(memories, &(&1["type"] == "discovery"))
    discoveries * 3
  end

  @doc "Travel memory modifier — penalize revisiting disliked locations."
  def travel_modifier(hero, destination_name) do
    memories = get_memories(hero)
    visits = Enum.count(memories, fn m -> m["type"] == "travel" and m["destination"] == destination_name end)
    _defeats_here = Enum.count(memories, fn m ->
      m["type"] == "defeat" and m["monster"] != nil  # approximate
    end)
    # Slight bonus for new places, slight penalty for repeated defeats
    if visits > 0, do: -2, else: 5
  end

  @doc "Get recent emotion tags for narrative context."
  def recent_emotions(hero, count \\ 5) do
    memories = get_memories(hero)
    memories
    |> Enum.take(-count)
    |> Enum.map(fn m ->
      case m["mood_impact"] || 0 do
        impact when impact > 10 -> "excited"
        impact when impact > 0 -> "content"
        impact when impact > -10 -> "neutral"
        _ -> "upset"
      end
    end)
  end

  defp append(hero, memory) do
    # Read fresh from DB to avoid stale state_data
    fresh_hero = Repo.get!(Hero, hero.id)
    state_data = decode(fresh_hero.state_data)
    memories = Map.get(state_data, "memories", [])
    new_memories = (memories ++ [memory]) |> Enum.take(-@max_memories)
    new_state = Map.put(state_data, "memories", new_memories)
    fresh_hero |> Ecto.Changeset.change(%{state_data: Jason.encode!(new_state)}) |> Repo.update!()
  end

  defp decode(state_data) do
    case Jason.decode(state_data || "{}") do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end
end

defmodule TesIdle.Game.Memory do
  @moduledoc """
  Hero emotional memory system.
  Tracks victories, defeats, discoveries, social encounters.
  Memories influence utility scores and narrative generation.
  """

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
      "mood_impact" => 10
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
      "mood_impact" => -20
    }

    append(hero, memory)
  end

  @doc "Add a discovery memory."
  def add_discovery(hero, what) do
    memory = %{
      "type" => "discovery",
      "what" => what,
      "day" => hero.game_day,
      "mood_impact" => 15
    }

    append(hero, memory)
  end

  @doc "Add a social memory."
  def add_social(hero, npc_name) do
    memory = %{
      "type" => "social",
      "npc" => npc_name,
      "day" => hero.game_day,
      "mood_impact" => 8
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
      "mood_impact" => 5
    }

    append(hero, memory)
  end

  @doc "Add a travel memory."
  def add_travel(hero, destination) do
    memory = %{
      "type" => "travel",
      "destination" => destination,
      "day" => hero.game_day,
      "mood_impact" => 3
    }

    append(hero, memory)
  end

  @doc "Add a quest completion memory."
  def add_quest_complete(hero, quest_name) do
    memory = %{
      "type" => "quest_complete",
      "quest" => quest_name,
      "day" => hero.game_day,
      "mood_impact" => 20
    }

    append(hero, memory)
  end

  @doc "Pure Pipeline helper: derive and append one precise memory from an action result."
  def track_action(state_data, hero, action_module, result, configs \\ %{}) do
    max_memories = get_in(configs || %{}, ["memory", "max_entries"]) || @max_memories

    case memory_for(hero, action_module, result) do
      nil -> state_data
      memory -> append_to_state_data(state_data, memory, max_memories)
    end
  end

  defp memory_for(hero, TesIdle.Game.Actions.FightAction, %{combat_result: combat}) do
    cond do
      combat[:victory] == true ->
        %{
          "type" => "victory",
          "monster" => combat[:monster_name] || "враг",
          "day" => hero.game_day,
          "gold_earned" => combat[:gold] || 0,
          "mood_impact" => 10
        }

      combat[:hero_defeated] == true ->
        %{
          "type" => "defeat",
          "monster" => combat[:monster_name] || "враг",
          "day" => hero.game_day,
          "gold_lost" => 0,
          "mood_impact" => -20
        }

      true ->
        %{
          "type" => "combat_stalemate",
          "monster" => combat[:monster_name] || "враг",
          "day" => hero.game_day,
          "rounds" => combat[:rounds],
          "mood_impact" => 0
        }
    end
  end

  defp memory_for(_hero, TesIdle.Game.Actions.FightAction, _result), do: nil

  defp memory_for(hero, TesIdle.Game.Actions.ExploreAction, result) do
    if (result[:gold_change] || 0) > 0 do
      %{
        "type" => "discovery",
        "what" => "здесь было найдено золото",
        "day" => hero.game_day,
        "mood_impact" => 15
      }
    end
  end

  defp memory_for(hero, TesIdle.Game.Actions.SocialAction, result) do
    context = result[:context] || %{}
    npc = context["npc_name"] || get_in(result, [:pet_adopted, :name])

    if is_binary(npc) and npc != "" do
      %{"type" => "social", "npc" => npc, "day" => hero.game_day, "mood_impact" => 8}
    end
  end

  defp memory_for(hero, TesIdle.Game.Actions.ShopAction, result) do
    if result[:item_name] do
      %{
        "type" => "shop",
        "item" => result[:item_name],
        "day" => hero.game_day,
        "gold_spent" => result[:gold_spent] || 0,
        "mood_impact" => 5
      }
    end
  end

  defp memory_for(hero, TesIdle.Game.Actions.TravelAction, result) do
    context = result[:context] || %{}
    destination = context["destination_name"]

    if context["travel_arrived"] == true and is_binary(destination) and destination != "" do
      %{
        "type" => "travel",
        "destination" => destination,
        "day" => hero.game_day,
        "mood_impact" => 3
      }
    end
  end

  defp memory_for(_hero, _action_module, _result), do: nil

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

    visits =
      Enum.count(memories, fn m ->
        m["type"] == "travel" and m["destination"] == destination_name
      end)

    _defeats_here =
      Enum.count(memories, fn m ->
        # approximate
        m["type"] == "defeat" and m["monster"] != nil
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

  @doc "Pure helper: append a memory to state_data for Pipeline's single save."
  def append_to_state_data(state_data, memory, max_memories \\ @max_memories)

  def append_to_state_data(state_data, memory, max_memories)
      when is_map(state_data) and is_map(memory) and is_integer(max_memories) and max_memories > 0 do
    memories = Map.get(state_data, "memories", [])
    Map.put(state_data, "memories", Enum.take(memories ++ [memory], -max_memories))
  end

  defp append(hero, memory) do
    hero.state_data
    |> decode()
    |> append_to_state_data(memory)
  end

  defp decode(state_data) do
    case Jason.decode(state_data || "{}") do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end
end

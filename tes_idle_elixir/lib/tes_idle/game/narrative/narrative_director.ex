defmodule TesIdle.Game.Narrative.NarrativeDirector do
  @moduledoc """
  Narrative Director: selects the best narrative event based on world context.
  Separates game logic from narrative generation.
  """

  alias TesIdle.Repo
  alias TesIdle.Game.{Personality}
  alias TesIdle.Game.Narrative.NarrativeEvent

  @dedup_count 10

  @doc "Select the best narrative event for the current context."
  def select(ctx, hero_state_data) do
    events = NarrativeEvent.all()

    # 1. Filter by required tags
    events = Enum.filter(events, fn ev ->
      Enum.all?(ev.requires, &(&1 in ctx.tags))
    end)

    # 2. Filter by forbidden tags
    events = Enum.filter(events, fn ev ->
      !Enum.any?(ev.forbids, &(&1 in ctx.tags))
    end)

    # 3. Chain bonus — boost events that follow the previous event
    prev_event = get_prev_event(hero_state_data)
    events = if prev_event do
      prev_ev = Enum.find(NarrativeEvent.all(), &(&1.name == prev_event))
      if prev_ev && prev_ev.chains != [] do
        Enum.map(events, fn ev ->
          if ev.name in prev_ev.chains do
            %{ev | weight: ev.weight * 3}
          else
            ev
          end
        end)
      else
        events
      end
    else
      events
    end

    # 4. Personality bonus — boost events matching hero traits
    events = apply_personality(events, ctx.personality || %{})

    # 4b. Memory bonus — boost events based on recent hero memories
    events = apply_memory(events, ctx.memories || [])

    # 5. Dedup — reduce weight of recently used events
    used = get_used_events(hero_state_data)
    events = Enum.map(events, fn ev ->
      if ev.name in used do
        # weight может быть float (chains ×3, memory-множители) — div/2 падает на float
        %{ev | weight: max(1, round(ev.weight / 3))}
      else
        ev
      end
    end)

    # 6. No valid events → fallback
    if events == [] do
      %NarrativeEvent{name: "generic_action", requires: [], forbids: [], weight: 1, chains: []}
    else
      weighted_random(events)
    end
  end

  @doc "Record that an event was used (dedup + chain tracking)."
  def track_used(hero, event_name) do
    # Свежее state_data из БД — не затираем brain/plan, записанные ранее в тике
    fresh = Repo.reload!(hero)
    state_data = decode(fresh.state_data)
    used = Map.get(state_data, "used_events", [])
    new_used = (used ++ [event_name]) |> Enum.take(-@dedup_count)

    new_state = state_data
    |> Map.put("used_events", new_used)
    |> Map.put("prev_event", event_name)

    fresh |> Ecto.Changeset.change(%{state_data: Jason.encode!(new_state)}) |> Repo.update!()
  end

  # --- Private ---

  defp apply_personality(events, personality) do
    if map_size(personality) == 0, do: events, else: events
      |> boost_for(Personality.trait(personality, :bravery) > 60, "brave", 2)
      |> boost_for(Personality.trait(personality, :curiosity) > 60, "curious", 2)
      |> boost_for(Personality.trait(personality, :caution) > 60, "cautious", 2)
  end

  defp apply_memory(events, memories) do
    if memories == [], do: events

    # Boost events matching recent memory types
    recent_types = memories
      |> Enum.take(-5)
      |> Enum.map(& &1["type"])

    has_victory = "victory" in recent_types
    has_defeat = "defeat" in recent_types
    has_discovery = "discovery" in recent_types
    has_social = "social" in recent_types

    events
    |> boost_for(has_victory, "victory", 1.5)
    |> boost_for(has_defeat, "defeat", 2.0)
    |> boost_for(has_discovery, "curious", 1.5)
    |> boost_for(has_social, "socializing", 1.3)
  end

  defp boost_for(events, true, tag, mult) do
    Enum.map(events, fn ev ->
      if tag in ev.requires do
        %{ev | weight: ev.weight * mult}
      else
        ev
      end
    end)
  end
  defp boost_for(events, _, _, _), do: events

  defp weighted_random(events) do
    # Множители памяти/личности (1.5, 2.0) делают weight float —
    # :rand.uniform/1 требует целое, иначе FunctionClauseError роняет тик.
    weighted = Enum.map(events, fn ev -> {ev, round(ev.weight)} end)
    total = Enum.reduce(weighted, 0, fn {_ev, w}, acc -> acc + w end)
    roll = :rand.uniform(max(total, 1))

    Enum.reduce_while(weighted, 0, fn {ev, w}, acc ->
      new_acc = acc + w
      if roll <= new_acc, do: {:halt, ev}, else: {:cont, new_acc}
    end) || List.first(events)
  end

  defp get_used_events(nil), do: []
  defp get_used_events(state_data) do
    case Jason.decode(state_data || "{}") do
      {:ok, data} when is_map(data) -> Map.get(data, "used_events", [])
      _ -> []
    end
  end

  defp get_prev_event(nil), do: nil
  defp get_prev_event(state_data) do
    case Jason.decode(state_data || "{}") do
      {:ok, data} when is_map(data) -> Map.get(data, "prev_event")
      _ -> nil
    end
  end

  defp decode(state_data) do
    case Jason.decode(state_data || "{}") do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end
end

defmodule TesIdle.Game.Brain.Audit do
  @moduledoc "Append-only decision telemetry kept independently from heroes.state_data."

  require Logger

  alias TesIdle.Repo
  alias TesIdle.Schemas.DecisionAuditEvent

  @doc "Records the intent created by Graph.log_decision/3 without writing hero state_data."
  def record_intent(ctx, previous_state_data, state_data) do
    if enabled?(ctx.configs) and decision_created?(previous_state_data, state_data) do
      brain = state_data["brain"] || %{}
      intent = brain["intent"] || %{}
      entry = List.last(brain["decision_log"] || []) || %{}

      event_type =
        cond do
          intent["switched"] == true -> "intent_switched"
          intent["held_decisions"] > 1 -> "intent_held"
          true -> "intent_selected"
        end

      insert(%{
        hero_id: ctx.hero.id,
        game_day: entry["day"] || ctx.hero.game_day,
        game_hour: entry["hour"] || ctx.hour,
        event_type: event_type,
        goal: intent["goal"] || entry["goal"],
        utility: entry["utility"] || intent["utility"],
        reasons: %{"items" => entry["reasons"] || []},
        metadata: %{
          "previous_goal" => intent["previous_goal"],
          "held_decisions" => intent["held_decisions"] || 1,
          "world" => entry["world"] || %{}
        }
      })
    end
  end

  def record_action(ctx, state_data, action_module, result, outcome) do
    if enabled?(ctx.configs) and action_module do
      intent = get_in(state_data, ["brain", "intent"]) || %{}
      action = action_name(action_module)

      base = %{
        hero_id: ctx.hero.id,
        game_day: ctx.hero.game_day,
        game_hour: ctx.hour,
        goal: intent["goal"],
        action: action,
        utility: intent["utility"],
        reasons: %{},
        metadata: action_metadata(result, intent)
      }

      if action_started?(ctx.hero.state_data, result),
        do: insert(Map.put(base, :event_type, "action_started"))

      cond do
        outcome == :failed -> insert(Map.put(base, :event_type, "action_failed"))
        terminal?(result) -> insert(Map.put(base, :event_type, "action_completed"))
        true -> :ok
      end
    end
  end

  def record_failed_action(ctx, state_data, action_module, reason) do
    record_action(ctx, state_data, action_module, %{error: reason}, :failed)
  end

  defp enabled?(configs), do: get_in(configs || %{}, ["brain", "audit", "enabled"]) != false

  defp decision_created?(previous, current) do
    previous_last = previous |> brain_log() |> List.last()
    current_last = current |> brain_log() |> List.last()
    current_last != nil and current_last != previous_last
  end

  defp brain_log(state_data) when is_map(state_data),
    do: get_in(state_data, ["brain", "decision_log"]) || []

  defp brain_log(_), do: []

  defp action_started?(state_data_json, result) do
    state_data = decode(state_data_json)

    cond do
      result[:combat_start] != nil ->
        true

      result[:state_to] == "traveling" and state_data["travel"] == nil ->
        true

      result[:state_to] in ["fishing", "mining", "jailed"] and
          state_data[result[:state_to]] == nil ->
        true

      result[:state_to] in ["fighting", "traveling", "fishing", "mining", "jailed"] ->
        false

      true ->
        true
    end
  end

  defp terminal?(result) do
    result[:combat_result] != nil or result[:activity_complete] == true or
      result[:state_to] not in ["fighting", "traveling", "fishing", "mining", "jailed"]
  end

  defp action_metadata(result, intent) do
    %{
      "state_to" => stringify(result[:state_to]),
      "outcome" => stringify(intent["last_outcome"]),
      "combat" => compact(result[:combat_result] || %{}),
      "error" => stringify(result[:error])
    }
  end

  defp compact(map) when is_map(map),
    do: Map.take(map, [:victory, :hero_defeated, :monster_name, :rounds]) |> stringify_keys()

  defp compact(_), do: %{}
  defp stringify_keys(map), do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)
  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp stringify(value), do: inspect(value)

  defp action_name(module),
    do:
      module
      |> Module.split()
      |> List.last()
      |> String.replace_suffix("Action", "")
      |> Macro.underscore()

  defp decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp decode(_), do: %{}

  # Audit is observational: telemetry outages must never abort a hero tick.
  defp insert(attrs) do
    try do
      case %DecisionAuditEvent{} |> DecisionAuditEvent.changeset(attrs) |> Repo.insert() do
        {:ok, _event} ->
          :ok

        {:error, changeset} ->
          Logger.warning("decision audit insert rejected: #{inspect(changeset.errors)}")
          :ok
      end
    rescue
      error ->
        Logger.warning("decision audit insert raised: #{Exception.message(error)}")
        :ok
    catch
      kind, reason ->
        Logger.warning("decision audit insert #{kind}: #{inspect(reason)}")
        :ok
    end
  end
end

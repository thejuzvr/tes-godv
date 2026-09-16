defmodule TesIdle.Game.FSMExecutor do
  @moduledoc """
  FSM Executor: manages hero state machine using Utility AI + GOAP plans.
  Returns {fsm_state, action_module, result, state_data}
  """

  alias TesIdle.Game.{Goal, GOAPPlanner, GameContext}

  @doc "Main tick: evaluates goals, manages plan, executes actions."
  def tick(%GameContext{} = ctx) do
    state_data = decode(ctx.hero)

    case get_fsm_state(state_data) do
      :jailed ->
        # Тюрьма — отдельная ветка FSM: план не трогаем, сидим/подкупаем/бежим
        jail_action = TesIdle.Game.Actions.JailAction
        {:ok, result_data} = jail_action.execute(ctx)

        if multi_tick?(result_data) do
          {:ok, jail_action, result_data, merge_state_data(state_data, result_data)}
        else
          {:ok, jail_action, result_data, Map.delete(state_data, "jail")}
        end

      :idle ->
        if state_data["travel"] do
          resume_travel(ctx, state_data)
        else
          create_and_execute(ctx, state_data)
        end

      :execute ->
        execute_plan_step(ctx, state_data)

      :fight ->
        # Combat in progress — always process combat round
        fight_action = TesIdle.Game.Actions.FightAction
        result = fight_action.execute(ctx)
        {:ok, result_data} = result
        if multi_tick?(result_data) do
          {:ok, fight_action, result_data, merge_state_data(state_data, result_data)}
        else
          # Бой завершён (победа/поражение/лимит раундов): шаг плана пройден.
          # S-2 верификация: без advance план зацикливался на шаге Fight —
          # герой вечно переигрывал бой и не принимал новых решений.
          {:ok, fight_action, result_data, advance_plan(Map.delete(state_data, "combat"))}
        end
    end
  end

  defp resume_travel(ctx, state_data) do
    # Random encounter during travel
    if encounter?(ctx) do
      fight_action = TesIdle.Game.Actions.FightAction
      result = fight_action.execute(ctx)
      case result do
        {:ok, %{combat_start: _} = result_data} ->
          # Combat started during travel — merge states
          {:ok, fight_action, result_data, merge_state_data(state_data, result_data)}
        _ ->
          # No monster — continue travel
          continue_travel(ctx, state_data)
      end
    else
      # Normal travel
      continue_travel(ctx, state_data)
    end
  end

  defp continue_travel(ctx, state_data) do
    travel_action = TesIdle.Game.Actions.TravelAction
    {:ok, result_data} = travel_action.execute(ctx)
    if multi_tick?(result_data) do
      {:ok, travel_action, result_data, merge_state_data(state_data, result_data)}
    else
      {:ok, travel_action, result_data, Map.delete(state_data, "travel")}
    end
  end

  defp encounter?(ctx) do
    danger = %{"dungeon" => 0.30, "wilderness" => 0.20, "village" => 0.10, "city" => 0.05}
    chance = Map.get(danger, ctx.location_type, 0.10)
    :rand.uniform() < chance
  end

  defp create_and_execute(ctx, state_data) do
    goal = Goal.best(ctx)
    plan = GOAPPlanner.plan(goal.name, ctx)
    plan = if plan == [], do: [TesIdle.Game.Actions.ExploreAction], else: plan

    # Мозг: лог решения («почему герой выбрал X»)
    state_data = TesIdle.Game.Brain.Graph.log_decision(state_data, goal, ctx)
    new_state = save_plan(state_data, goal.name, plan)
    [first_action | _rest] = plan

    result = first_action.execute(ctx)
    case result do
      {:ok, result_data} ->
        if multi_tick?(result_data) do
          {:ok, first_action, result_data, merge_state_data(new_state, result_data)}
        else
          {:ok, first_action, result_data, advance_plan(new_state)}
        end
      {:error, _} ->
        {:ok, first_action, nil, clear_plan(new_state)}
    end
  end

  defp execute_plan_step(ctx, state_data) do
    plan = get_plan(state_data)

    case plan do
      [] ->
        {:ok, nil, nil, clear_plan(state_data)}

      [action_module | _rest] ->
        case action_module.execute(ctx) do
          {:ok, result_data} ->
            if multi_tick?(result_data) do
              {:ok, action_module, result_data, merge_state_data(state_data, result_data)}
            else
              {:ok, action_module, result_data, advance_plan(state_data)}
            end

          {:error, _} ->
            {:ok, action_module, nil, clear_plan(state_data)}
        end
    end
  end

  defp multi_tick?(result) do
    result[:state_to] in ["fighting", "traveling", "fishing", "jailed"] ||
      result[:combat_progress] != nil ||
      result[:combat_start] != nil ||
      (result[:state_data_update] && result[:state_data_update]["combat"]) ||
      (result[:state_data_update] && result[:state_data_update]["travel"]) ||
      (result[:state_data_update] && result[:state_data_update]["fishing"]) ||
      (result[:state_data_update] && result[:state_data_update]["jail"])
  end

  defp save_plan(state_data, goal_name, plan) do
    plan_data = %{
      "goal" => to_string(goal_name),
      "steps" => Enum.map(plan, fn mod -> to_string(mod) end),
      "current_step" => 0,
    }
    Map.put(state_data, "plan", plan_data)
  end

  defp get_plan(state_data) do
    plan_data = state_data["plan"]
    if plan_data do
      steps = plan_data["steps"] || []
      current = plan_data["current_step"] || 0
      remaining = Enum.drop(steps, current)

      Enum.map(remaining, fn step_str ->
        case step_str do
          "Elixir.TesIdle.Game.Actions.ExploreAction" -> TesIdle.Game.Actions.ExploreAction
          "Elixir.TesIdle.Game.Actions.FightAction" -> TesIdle.Game.Actions.FightAction
          "Elixir.TesIdle.Game.Actions.RestAction" -> TesIdle.Game.Actions.RestAction
          "Elixir.TesIdle.Game.Actions.ShopAction" -> TesIdle.Game.Actions.ShopAction
          "Elixir.TesIdle.Game.Actions.SocialAction" -> TesIdle.Game.Actions.SocialAction
          "Elixir.TesIdle.Game.Actions.TravelAction" -> TesIdle.Game.Actions.TravelAction
          "Elixir.TesIdle.Game.Actions.LootAction" -> TesIdle.Game.Actions.LootAction
          "Elixir.TesIdle.Game.Actions.DeathAction" -> TesIdle.Game.Actions.DeathAction
          "Elixir.TesIdle.Game.Actions.FishingAction" -> TesIdle.Game.Actions.FishingAction
          "Elixir.TesIdle.Game.Actions.GatheringAction" -> TesIdle.Game.Actions.GatheringAction
          "Elixir.TesIdle.Game.Actions.StealingAction" -> TesIdle.Game.Actions.StealingAction
          "Elixir.TesIdle.Game.Actions.BreakInAction" -> TesIdle.Game.Actions.BreakInAction
          "Elixir.TesIdle.Game.Actions.JailAction" -> TesIdle.Game.Actions.JailAction
          "Elixir.TesIdle.Game.Actions.PetCareAction" -> TesIdle.Game.Actions.PetCareAction
          _ -> TesIdle.Game.Actions.ExploreAction
        end
      end)
    else
      []
    end
  end

  defp advance_plan(state_data) do
    plan_data = state_data["plan"]
    if plan_data do
      current = plan_data["current_step"] || 0
      new_plan = Map.put(plan_data, "current_step", current + 1)
      total = length(new_plan["steps"] || [])

      if current + 1 >= total do
        Map.delete(state_data, "plan")
      else
        Map.put(state_data, "plan", new_plan)
      end
    else
      state_data
    end
  end

  defp clear_plan(state_data) do
    Map.delete(state_data, "plan")
  end

  defp merge_state_data(state_data, result) do
    if result[:state_data_update] do
      Map.merge(state_data, result[:state_data_update])
    else
      state_data
    end
  end

  defp get_fsm_state(state_data) do
    cond do
      state_data["combat"] -> :fight
      state_data["jail"] -> :jailed
      state_data["plan"] -> :execute
      state_data["travel"] -> :idle
      true -> :idle
    end
  end

  defp decode(hero) do
    case Jason.decode(hero.state_data || "{}") do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end
end

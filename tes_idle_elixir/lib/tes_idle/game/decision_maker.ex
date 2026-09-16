defmodule TesIdle.Game.DecisionMaker do
  @moduledoc """
  Scores all actions based on context, applies behavior chains,
  and selects the next action via weighted random.
  """

  alias TesIdle.Game.{GameContext, BehaviorChains}

  @actions [
    TesIdle.Game.Actions.ExploreAction,
    TesIdle.Game.Actions.FightAction,
    TesIdle.Game.Actions.RestAction,
    TesIdle.Game.Actions.ShopAction,
    TesIdle.Game.Actions.SocialAction,
    TesIdle.Game.Actions.TravelAction,
    TesIdle.Game.Actions.LootAction,
    TesIdle.Game.Actions.DeathAction,
  ]

  def decide(%GameContext{} = ctx) do
    # Score all actions
    scores = Enum.map(@actions, fn action ->
      {action, action.score(ctx)}
    end)

    # Apply behavior chains
    scores = BehaviorChains.apply(scores, ctx)

    # Weighted random selection
    weighted_random(scores)
  end

  defp weighted_random(scores) do
    # Filter out zero/negative scores
    valid = Enum.filter(scores, fn {_, score} -> score > 0 end)

    case valid do
      [] -> {List.first(@actions), 1}  # Fallback to explore
      _ ->
        total = Enum.reduce(valid, 0, fn {_, score}, acc -> acc + score end)
        roll = :rand.uniform(total)

        {chosen, _} = Enum.reduce_while(valid, {nil, 0}, fn {action, score}, {_, acc} ->
          new_acc = acc + score
          if roll <= new_acc, do: {:halt, {action, new_acc}}, else: {:cont, {action, new_acc}}
        end)

        if chosen, do: {chosen, 1}, else: {List.first(@actions), 1}
    end
  end
end

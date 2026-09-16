defmodule TesIdle.Game.BehaviorChains do
  @moduledoc """
  Temporal modifiers based on hero's recent actions.
  Creates coherent behavior sequences (e.g., fight → loot → rest).
  """

  alias TesIdle.Game.GameContext

  def apply(scores, %GameContext{} = ctx) do
    last_state = ctx.hero.state

    case last_state do
      "fighting" ->
        scores
        |> add_score(TesIdle.Game.Actions.LootAction, 15)
        |> add_score(TesIdle.Game.Actions.RestAction, 10)

      "looting" ->
        add_score(scores, TesIdle.Game.Actions.ExploreAction, 10)

      "resting" ->
        scores
        |> add_score(TesIdle.Game.Actions.ExploreAction, 10)
        |> add_score(TesIdle.Game.Actions.ShopAction, 8)

      "shopping" ->
        scores
        |> add_score(TesIdle.Game.Actions.ExploreAction, 10)
        |> add_score(TesIdle.Game.Actions.SocialAction, 8)

      "socializing" ->
        scores
        |> add_score(TesIdle.Game.Actions.ExploreAction, 8)
        |> add_score(TesIdle.Game.Actions.RestAction, 8)

      _ ->
        scores
    end
  end

  defp add_score(scores, action_module, bonus) do
    Enum.map(scores, fn {action, score} ->
      if action == action_module do
        {action, score + bonus}
      else
        {action, score}
      end
    end)
  end
end

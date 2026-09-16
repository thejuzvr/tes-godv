defmodule TesIdle.Game.Actions.DeathAction do
  @moduledoc "Hero dies and respawns."
  @behaviour TesIdle.Game.Action

  alias TesIdle.Game.GameContext

  @impl true
  def score(%GameContext{} = ctx) do
    if ctx.hero.hp <= 0, do: 1000, else: 0
  end

  @impl true
  def execute(%GameContext{} = ctx) do
    gold_loss = trunc(ctx.hero.gold * 0.1)

    {:ok, %{
      state_to: "resting",
      hp_change: ctx.hero.max_hp - ctx.hero.hp,
      gold_change: -gold_loss,
    }}
  end
end

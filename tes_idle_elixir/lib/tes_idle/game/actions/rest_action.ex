defmodule TesIdle.Game.Actions.RestAction do
  @moduledoc "Hero rests — inn or outdoor with different bonuses."
  @behaviour TesIdle.Game.Action

  alias TesIdle.Game.GameContext

  @impl true
  def score(%GameContext{} = ctx) do
    base = location_weight(ctx.location_type, :resting)
    base = if ctx.needs.fatigue > 70, do: base + 25, else: base
    base = if ctx.hero.hp < ctx.hero.max_hp * 0.3, do: base + 30, else: base
    if ctx.hour >= 22 or ctx.hour < 6, do: base + 25, else: base
  end

  @impl true
  def execute(%GameContext{} = ctx) do
    has_inn = ctx.location && ctx.location.has_inn
    extra = TesIdle.Game.Passives.bonus(ctx.hero).rest

    if has_inn do
      heal = Enum.random(15..45) + extra
      fatigue_reduction = Enum.random(15..35)
      {:ok, %{
        state_to: "resting",
        hp_change: min(heal, ctx.hero.max_hp - ctx.hero.hp),
        mp_change: 10,
        sp_change: 15,
        hunger_change: Enum.random(-5..-2),
        fatigue_change: -fatigue_reduction,
      }}
    else
      heal = Enum.random(10..30) + extra
      fatigue_reduction = Enum.random(10..25)
      {:ok, %{
        state_to: "resting",
        hp_change: min(heal, ctx.hero.max_hp - ctx.hero.hp),
        sp_change: 5,
        hunger_change: Enum.random(-5..-2),
        fatigue_change: -fatigue_reduction,
      }}
    end
  end

  defp location_weight("village", :resting), do: 20
  defp location_weight("city", :resting), do: 20
  defp location_weight(_, :resting), do: 10
end

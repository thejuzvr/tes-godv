defmodule TesIdle.Game.Actions.SocialAction do
  @moduledoc "Hero socializes at tavern."
  @behaviour TesIdle.Game.Action

  alias TesIdle.Game.GameContext

  @impl true
  def score(%GameContext{} = ctx) do
    base = if ctx.location && ctx.location.has_inn, do: 15, else: 0
    base = if ctx.needs.morale < 30, do: base + 20, else: base
    if ctx.hour >= 18 and ctx.hour < 22, do: base + 15, else: base
  end

  @impl true
  def execute(%GameContext{} = ctx) do
    gold_change = if :rand.uniform() < 0.15 do
      Enum.random([-30..-5, 5..30]) |> Enum.random()
    else
      0
    end

    # Усыновление питомца: редкий шанс на социализации (если питомца нет)
    cfg = ((ctx.configs || %{})["activities"] || %{})["pets"] || %{}
    adopted = TesIdle.Game.Pets.maybe_adopt(ctx.hero, cfg)

    result = %{
      state_to: "socializing",
      gold_change: gold_change,
      morale_change: Enum.random(3..8) + if(adopted, do: 8, else: 0),
    }

    # Контракт Action: {:ok, map} — FSM/Pipeline матчатся на {:ok, _}/{:error, _}
    if adopted do
      {:ok, Map.put(result, :pet_adopted, %{name: adopted.name, species: adopted.species})}
    else
      {:ok, result}
    end
  end
end

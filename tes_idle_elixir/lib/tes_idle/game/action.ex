defmodule TesIdle.Game.Action do
  @moduledoc """
  Behaviour for game actions.
  Each action module implements score/1 and execute/1.
  """

  @callback score(context :: TesIdle.Game.GameContext.t()) :: integer()
  @callback execute(context :: TesIdle.Game.GameContext.t()) :: {:ok, map()} | {:error, term()}
end

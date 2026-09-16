defmodule TesIdle.World.State do
  @moduledoc """
  Читатель снапшота ядра мира (ROADMAP Часть III).

  WorldKernel — единственный писатель; все остальные (ContextBuilder,
  actions) читают через этот модуль. Значения — JSONB-карты по ключам:
  "world_day", "weather", "economy", "density", "factions", "kernel".
  """

  alias TesIdle.Repo
  alias TesIdle.Schemas.WorldState

  @doc "Вся карта состояния по ключу (или default)."
  def get(key, default \\ %{}) do
    case Repo.get(WorldState, key) do
      nil -> default
      row -> row.value || default
    end
  end

  @doc "Поле внутри карты состояния."
  def get_field(key, field, default \\ nil) when is_binary(field) do
    key |> get() |> Map.get(field, default)
  end

  @doc "Все ключи состояния."
  def all_keys do
    Repo.all(WorldState) |> Map.new(&{&1.key, &1.value || %{}})
  end
end

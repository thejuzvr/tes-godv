defmodule TesIdle.Game.Actions.PetCareAction do
  @moduledoc """
  Уход за питомцем (ROADMAP Часть II): кормить / играть / дрессировать.
  Выбор заботы — по состоянию питомца и эмпатии хозяина.
  Если питомца нет — герой осмотрится (explore): усыновление случается
  на социализации (Pets.maybe_adopt), не здесь.
  """
  @behaviour TesIdle.Game.Action

  alias TesIdle.Game.{GameContext, Pets}

  @impl true
  def score(%GameContext{} = _ctx), do: 50

  @impl true
  def execute(%GameContext{} = ctx) do
    cfg = ((ctx.configs || %{})["activities"] || %{})["pets"] || %{}
    pet = Pets.active(ctx.hero.id)

    if pet do
      care(ctx, pet, cfg)
    else
      TesIdle.Game.Actions.ExploreAction.execute(ctx)
    end
  end

  defp care(ctx, pet, cfg) do
    empathy = Map.get(ctx.personality || %{}, :empathy, 50)

    # Выбор заботы: голодный — кормим; грустный — играем; иначе дрессировка
    {kind, updated_pet, gold_cost} = cond do
      pet.hunger >= 60.0 and ctx.hero.gold >= (cfg["feed_cost"] || 8) ->
        {:feed, Pets.feed(pet, cfg), cfg["feed_cost"] || 8}

      pet.mood <= 45.0 ->
        {:play, Pets.play(pet, cfg), 0}

      true ->
        {:train, Pets.train(pet, cfg), 0}
    end

    # Кот гладится: немного настроения хозяину
    cat_bonus = Pets.cat_mood_bonus(pet, cfg)

    {:ok, %{
      state_to: "pet_care",
      gold_change: -gold_cost,
      morale_change: if(kind == :play, do: 4 + trunc(empathy / 25), else: cat_bonus),
      state_data_update: %{"pet_care" => %{"kind" => to_string(kind), "pet" => updated_pet.name}},
      context: %{
        "pet_name" => updated_pet.name,
        "pet_care_kind" => care_label(kind),
        "pet_loyalty" => trunc(updated_pet.loyalty),
        "pet_species" => pet_species_ru(updated_pet.species),
      },
    }}
  end

  defp care_label(:feed), do: "покормил"
  defp care_label(:play), do: "поиграл"
  defp care_label(:train), do: "поучил командам"

  defp pet_species_ru("wolf"), do: "волк"
  defp pet_species_ru("owl"), do: "сова"
  defp pet_species_ru("cat"), do: "кот"
  defp pet_species_ru("lizard"), do: "ящерица"
  defp pet_species_ru(other), do: to_string(other)
end

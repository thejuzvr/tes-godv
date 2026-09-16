defmodule TesIdle.Game.GOAPPlanner do
  @moduledoc """
  GOAP (Goal-Oriented Action Planning) planner.
  Given a goal, builds a sequence of actions to achieve it.
  Uses simple forward-chaining search.
  """

  alias TesIdle.Repo

  @max_plan_length 8

  @action_configs %{
    complete_quest: %{
      steps: [:explore, :fight, :shop, :rest],
    },
    heal: %{
      steps: [:rest],
    },
    rest: %{
      steps: [:rest],
    },
    explore: %{
      steps: [:explore],
    },
    fight: %{
      steps: [:fight],
    },
    shop: %{
      steps: [:shop],
    },
    socialize: %{
      steps: [:socialize],
    },
    travel: %{
      steps: [:travel],
    },
    loot: %{
      steps: [:loot],
    },
    fish: %{
      steps: [:fish],
    },
    gather: %{
      steps: [:gather],
    },
    mining: %{
      steps: [:mining],
    },
    steal: %{
      steps: [:steal],
    },
    break_in: %{
      steps: [:break_in],
    },
    pet_care: %{
      steps: [:pet_care],
    },
  }

  @action_to_module %{
    explore: TesIdle.Game.Actions.ExploreAction,
    fight: TesIdle.Game.Actions.FightAction,
    rest: TesIdle.Game.Actions.RestAction,
    shop: TesIdle.Game.Actions.ShopAction,
    socialize: TesIdle.Game.Actions.SocialAction,
    travel: TesIdle.Game.Actions.TravelAction,
    loot: TesIdle.Game.Actions.LootAction,
    fish: TesIdle.Game.Actions.FishingAction,
    gather: TesIdle.Game.Actions.GatheringAction,
    mining: TesIdle.Game.Actions.MiningAction,
    steal: TesIdle.Game.Actions.StealingAction,
    break_in: TesIdle.Game.Actions.BreakInAction,
    pet_care: TesIdle.Game.Actions.PetCareAction,
  }

  @doc "Build a plan (list of action modules) for a given goal."
  def plan(goal_name, ctx) do
    _config = Map.get(@action_configs, goal_name, %{steps: [:explore]})

    steps = case goal_name do
      :complete_quest -> build_quest_plan(ctx)
      :heal -> [:rest]
      :rest -> [:rest]
      :explore -> [:explore]
      :fight -> [:fight]
      :shop -> [:shop]
      :socialize -> [:socialize]
      :travel -> [:travel]
      :loot -> [:loot]
      :fish -> [:fish]
      :gather -> [:gather]
      :mining -> [:mining]
      :steal -> [:steal]
      :break_in -> [:break_in]
      :pet_care -> [:pet_care]
      _ -> [:explore]
    end

    # Map step names to modules
    steps
    |> Enum.take(@max_plan_length)
    |> Enum.map(fn step -> Map.get(@action_to_module, step, TesIdle.Game.Actions.ExploreAction) end)
  end

  defp build_quest_plan(ctx) do
    case ctx.active_quest do
      nil -> [:explore]
      aq ->
        step_type = get_step_type(aq)
        quest = Repo.get!(TesIdle.Schemas.Quest, aq.quest_id)

        needs_travel = quest.location_id && quest.location_id != ctx.hero.location_id

        # Фаза 2 (аудит): колектор-шаг вне города/деревни с магазином —
        # невыполнимый план (ShopAction ошибается → план чистится → цикл).
        # Везде идём пешком: exploring может привести к нужному месту.
        can_shop_here? = ctx.location_type in ["city", "village"] && ctx.location && ctx.location.has_shop

        case step_type do
          "kill" ->
            if needs_travel, do: [:travel, :fight], else: [:explore, :fight]
          "explore" -> [:explore]
          "collect" -> if can_shop_here?, do: [:shop], else: [:travel, :shop]
          "travel" ->
            if needs_travel, do: [:travel], else: [:explore]
          _ -> [:explore]
        end
    end
  end

  defp get_step_type(aq) do
    alias TesIdle.Repo
    alias TesIdle.Schemas.QuestStep
    import Ecto.Query

    step = Repo.one(
      from s in QuestStep,
        where: s.quest_id == ^aq.quest_id and s.step_order == ^aq.current_step,
        limit: 1,
        select: s.step_type
    )
    step || "explore"
  end
end

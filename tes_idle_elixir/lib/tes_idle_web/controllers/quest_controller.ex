defmodule TesIdleWeb.QuestController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Quest, QuestStep, ActiveQuest}
  import Ecto.Query

  def active(conn, _params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)

    if is_nil(hero) do
      conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})
    else
      active = Repo.one(
        from aq in ActiveQuest,
          where: aq.hero_id == ^hero.id,
          join: q in Quest, on: q.id == aq.quest_id,
          preload: [quest: q]
      )

      if active do
        quest_id = active.quest_id
        steps = Repo.all(from s in QuestStep, where: s.quest_id == ^quest_id, order_by: s.step_order)
        json(conn, %{
          id: active.quest.id,
          name: active.quest.name,
          description: active.quest.description,
          difficulty: active.quest.difficulty,
          current_step: active.current_step,
          steps_total: active.quest.steps_total,
          xp_reward: active.quest.xp_reward,
          gold_reward: active.quest.gold_reward,
          steps: Enum.map(steps, fn s ->
            status = cond do
              s.step_order < active.current_step -> "done"
              s.step_order == active.current_step -> "active"
              true -> "pending"
            end
            %{description: s.description, status: status}
          end)
        })
      else
        json(conn, nil)
      end
    end
  end

  def generate(conn, _params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    existing = if hero, do: Repo.one(from aq in ActiveQuest, where: aq.hero_id == ^hero.id)

    cond do
      is_nil(hero) ->
        conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})

      not is_nil(existing) ->
        conn |> put_status(:bad_request) |> json(%{detail: "Already has active quest"})

      true ->
        # Generate a simple quest (simplified)
        quest = Repo.insert!(%Quest{
          name: "Исследовать окрестности",
          description: "Найди 3 новые находки в текущей локации",
          difficulty: "Лёгкий",
          xp_reward: 50,
          gold_reward: 25,
          steps_total: 3,
        })

        Repo.insert!(%QuestStep{quest_id: quest.id, step_order: 1, description: "Найти находку #1", step_type: "explore", target_count: 1})
        Repo.insert!(%QuestStep{quest_id: quest.id, step_order: 2, description: "Найти находку #2", step_type: "explore", target_count: 1})
        Repo.insert!(%QuestStep{quest_id: quest.id, step_order: 3, description: "Найти находку #3", step_type: "explore", target_count: 1})

        Repo.insert!(%ActiveQuest{hero_id: hero.id, quest_id: quest.id})

        json(conn, %{message: "Quest generated", quest_id: quest.id})
    end
  end

  def accept(conn, %{"id" => quest_id}) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    quest = Repo.get(Quest, quest_id)
    existing = if hero, do: Repo.one(from aq in ActiveQuest, where: aq.hero_id == ^hero.id)

    cond do
      is_nil(hero) ->
        conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})

      is_nil(quest) ->
        conn |> put_status(:not_found) |> json(%{detail: "Quest not found"})

      not is_nil(existing) ->
        conn |> put_status(:bad_request) |> json(%{detail: "Already has active quest"})

      true ->
        Repo.insert!(%ActiveQuest{hero_id: hero.id, quest_id: quest.id})
        json(conn, %{message: "Quest accepted"})
    end
  end

  def complete(conn, _params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    active = if hero, do: Repo.one(from aq in ActiveQuest, where: aq.hero_id == ^hero.id, preload: [:quest])

    cond do
      is_nil(hero) ->
        conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})

      is_nil(active) ->
        conn |> put_status(:not_found) |> json(%{detail: "No active quest"})

      true ->
        # Grant rewards
        hero |> Hero.changeset(%{
          xp: hero.xp + active.quest.xp_reward,
          gold: hero.gold + active.quest.gold_reward,
        }) |> Repo.update!()

        Repo.delete!(active)
        json(conn, %{message: "Quest completed", xp: active.quest.xp_reward, gold: active.quest.gold_reward})
    end
  end
end

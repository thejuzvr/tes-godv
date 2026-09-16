defmodule TesIdleWeb.GodController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, JournalEntry}
  alias TesIdle.Game.Narrative.TemplateEngine
  import Ecto.Query

  @effects %{
    "encourage" => %{"morale" => 15, "mood" => 10},
    "punish" => %{"morale" => -10, "mood" => -10},
    "heal" => %{"hp" => 30},
    "direct" => %{},
    "quest" => %{},
    "weather" => %{},
  }

  @template_types %{
    "encourage" => "god_encourage",
    "punish" => "god_punish",
    "heal" => "god_heal",
    "direct" => "god_direct",
    "quest" => "god_quest",
    "weather" => "god_weather",
  }

  @fallback_texts %{
    "encourage" => "Чувство уверенности наполнило героя.",
    "punish" => "Земля содрогнулась рядом с героем.",
    "heal" => "Целебная энергия пробежала по телу.",
    "direct" => "Ноги сами понесли героя вперёд.",
    "quest" => "Перед глазами появилось видение.",
    "weather" => "Небо затянуло тучами.",
  }

  def handle_action(conn, %{"action_type" => action_type}) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id, preload: [:location])

    effects = @effects[action_type]
    # Soul energy costs
    costs = %{"encourage" => 5, "punish" => 5, "heal" => 10, "direct" => 10, "quest" => 15, "weather" => 5}
    cost = Map.get(costs, action_type, 0)

    cond do
      is_nil(hero) ->
        conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})

      is_nil(effects) ->
        conn |> put_status(:bad_request) |> json(%{detail: "Unknown action type: #{action_type}"})

      hero.soul_energy < cost ->
        conn |> put_status(:bad_request) |> json(%{detail: "Not enough soul energy"})

      true ->
        # Apply effects
        updates = %{soul_energy: hero.soul_energy - cost}
        updates = if effects["morale"], do: Map.put(updates, :morale, max(0, min(100, hero.morale + effects["morale"]))), else: updates
        updates = if effects["mood"], do: Map.put(updates, :mood, max(0, min(100, hero.mood + effects["mood"]))), else: updates
        updates = if effects["hp"], do: Map.put(updates, :hp, min(hero.max_hp, hero.hp + effects["hp"])), else: updates

        if map_size(updates) > 0 do
          Repo.update!(Hero.changeset(hero, updates))
        end

        # Generate narrative via TemplateEngine
        template_type = @template_types[action_type] || "god_encourage"
        ctx = %{hero: hero, location: hero.location, configs: %{}, hour: 8,
                location_type: if(hero.location, do: hero.location.location_type, else: "wilderness"),
                mood: hero.mood}
        result = %{state_to: template_type}

        narrative = TemplateEngine.generate(result, ctx)
        text = narrative.text || @fallback_texts[action_type] || "#{hero.name} ощутил присутствие бога."

        Repo.insert!(%JournalEntry{hero_id: hero.id, entry_type: "god", text: text})

        json(conn, %{message: "God action applied", narrative: text})
    end
  end
end

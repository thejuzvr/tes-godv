defmodule TesIdleWeb.HeroController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Location}
  import Ecto.Query

  def create(conn, %{"name" => name, "race" => race, "hero_class" => hero_class}) do
    user = conn.assigns.current_user
    uid = user.id

    existing = Repo.one(from h in Hero, where: h.user_id == ^uid)
    if existing do
      conn |> put_status(:bad_request) |> json(%{detail: "Hero already exists"})
    else
      start_loc = Repo.one(from l in Location, where: l.location_type == "village", limit: 1)
      # Мозг героя: детерминированный геном из паспорта (ROADMAP Часть I)
      brain_hash = TesIdle.Game.Brain.Genome.brain_hash(uid)
      personality = TesIdle.Game.Personality.generate(race, hero_class, brain_hash: brain_hash)
      hero = %Hero{
        user_id: uid, name: name, race: race, hero_class: hero_class,
        location_id: if(start_loc, do: start_loc.id),
        personality: personality,
        brain_hash: brain_hash,
        skills: %{},
      }
      case Repo.insert(hero) do
        {:ok, hero} -> json(conn, hero_response(hero))
        {:error, _} -> conn |> put_status(:unprocessable_entity) |> json(%{detail: "Failed"})
      end
    end
  end

  def me(conn, _params) do
    uid = conn.assigns.current_user.id
    hero = Repo.one(from h in Hero, where: h.user_id == ^uid, preload: [:location, :equipment])
    if hero, do: json(conn, hero_response(hero)), else: conn |> put_status(:not_found) |> json(%{detail: "No hero"})
  end

  @doc "Репутация героя по фракциям (таблица reputations, LawSystem + P-3)."
  def reputations(conn, _params) do
    uid = conn.assigns.current_user.id
    hero = Repo.one(from h in Hero, where: h.user_id == ^uid)

    if hero do
      reps =
        Repo.all(
          from r in TesIdle.Schemas.Reputation,
            where: r.hero_id == ^hero.id,
            order_by: r.faction,
            select: %{faction: r.faction, value: r.value, level: r.level}
        )

      json(conn, %{reputations: reps, thresholds: TesIdle.Game.Law.rep_cfg(%{})["thresholds"]})
    else
      conn |> put_status(:not_found) |> json(%{detail: "No hero"})
    end
  end

  @doc false
  defp visible_pets(hero_id) do
    pets = TesIdle.Game.Pets.any_pets(hero_id)
    has_living? = Enum.any?(pets, &(&1.status in ["active", "cooldown"]))

    if has_living? do
      Enum.filter(pets, &(&1.status in ["active", "cooldown"]))
    else
      # Нет живого питомца: показываем последнего ушедшего как «память» на главной
      case Enum.find(pets, &(&1.status == "gone")) do
        nil -> pets
        gone -> [gone]
      end
    end
  end

  @doc "История питомцев (P-1): все ушедшие (gone), новые — первыми."
  def pets_history(conn, _params) do
    uid = conn.assigns.current_user.id
    hero = Repo.one(from h in Hero, where: h.user_id == ^uid)

    if hero do
      history =
        TesIdle.Game.Pets.history(hero.id)
        |> Enum.map(&pet_map/1)

      json(conn, %{pets: history})
    else
      conn |> put_status(:not_found) |> json(%{detail: "No hero"})
    end
  end

  defp pet_map(p) do
    %{
      id: p.id, species: p.species, name: p.name,
      mood: p.mood, hunger: p.hunger, loyalty: p.loyalty,
      status: p.status, revive_at: p.revive_at,
      created_at: p.created_at,
    }
  end

  def heartbeat(conn, _params) do
    uid = conn.assigns.current_user.id
    hero = Repo.one(from h in Hero, where: h.user_id == ^uid)
    if hero do
      hero |> Hero.changeset(%{last_activity: DateTime.utc_now(), is_online: true}) |> Repo.update!()
      json(conn, %{status: "ok", is_online: true})
    else
      conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})
    end
  end

  def offline(conn, _params) do
    uid = conn.assigns.current_user.id
    hero = Repo.one(from h in Hero, where: h.user_id == ^uid)
    if hero do
      hero |> Hero.changeset(%{is_online: false}) |> Repo.update!()
      json(conn, %{status: "ok", is_online: false})
    else
      conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})
    end
  end

  @doc "GET /api/v1/hero/brain — паспорт мозга для страницы «Аналитика» (владелец-only)."
  def brain(conn, _params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)

    if hero do
      alias TesIdle.Game.Brain.{Genome, Graph}

      legacy? = is_nil(hero.brain_hash)
      hash = hero.brain_hash || Genome.brain_hash(user.id)
      genome = Genome.derive(hash)
      brain_state = Graph.read_brain_state(hero)
      {links, base_links} = Graph.current_links(hero)

      links_payload =
        Map.new(links, fn {key, w} ->
          base = Map.get(base_links, key, w)
          [a, b] = String.split(key, "~")
          {key, %{"a" => a, "b" => b, "weight" => w, "base_weight" => base}}
        end)

      traits = TesIdle.Game.Personality.normalize(hero.personality)
        |> Enum.map(fn {t, v} -> %{"trait" => Atom.to_string(t), "value" => v,
                                  "base" => if(legacy?, do: nil, else: Map.get(genome.traits, t))} end)

      mood_history =
        case Jason.decode(hero.mood_history || "[]") do
          {:ok, list} when is_list(list) -> list
          _ -> []
        end

      json(conn, %{
        brain_hash: hash,
        legacy: legacy?,
        generation: brain_state["generation"] || 1,
        archetype: Atom.to_string(genome.archetype_hint),
        quirks: Enum.map(genome.quirks, &Atom.to_string/1),
        traits: traits,
        links: Map.values(links_payload),
        decision_log: brain_state["decision_log"] || [],
        budget: brain_state["budget"] || %{"week" => 1, "spent" => 0.0},
        mood_history: mood_history,
        stats: %{
          total_kills: hero.total_kills,
          total_gold_earned: hero.total_gold_earned,
          total_play_time_seconds: hero.total_play_time_seconds,
          game_day: hero.game_day,
          level: hero.level,
          name: hero.name,
        },
      })
    else
      conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})
    end
  end

  defp hero_response(hero) do
    hero = Repo.preload(hero, [:location, :equipment])

    pets = visible_pets(hero.id) |> Enum.map(&pet_map/1)

    guild_block = guild_block(hero.user_id)

    %{
      id: hero.id, name: hero.name, race: hero.race, hero_class: hero.hero_class,
      level: hero.level, hp: hero.hp, max_hp: hero.max_hp,
      mp: hero.mp, max_mp: hero.max_mp, sp: hero.sp, max_sp: hero.max_sp,
      attack: hero.attack, defense: hero.defense,
      xp: hero.xp, xp_to_next: hero.xp_to_next, gold: hero.gold,
      state: hero.state, mood: hero.mood,
      hunger: hero.hunger, fatigue: hero.fatigue, morale: hero.morale,
      soul_energy: hero.soul_energy,
      game_hour: hero.game_hour, game_day: hero.game_day, game_era: hero.game_era,
      total_play_time_seconds: hero.total_play_time_seconds,
      total_gold_earned: hero.total_gold_earned, total_kills: hero.total_kills,
      is_online: hero.is_online, state_data: hero.state_data,
      personality: hero.personality, mood_history: hero.mood_history,
      pets: pets,
      bounty: TesIdle.Game.Law.total_bounty(hero),
      guild: guild_block,
      location: if(hero.location, do: %{
        id: hero.location.id, name: hero.location.name, region: hero.location.region,
        location_type: hero.location.location_type, has_shop: hero.location.has_shop,
        has_inn: hero.location.has_inn, weather: hero.location.weather,
        danger_level: hero.location.danger_level, min_level: hero.location.min_level,
        max_level: hero.location.max_level,
      }),
    }
  end

  # G-1: гильдия героя в hero_response — дашборд показывает строку бафа
  defp guild_block(user_id) do
    case TesIdle.Game.Guilds.membership(user_id) do
      {guild, member} ->
        buff = TesIdle.Game.Guilds.buff_for(guild.level, TesIdle.Game.Guilds.cfg(%{}))

        %{
          id: guild.id, name: guild.name, emblem: guild.emblem,
          level: guild.level, role: member.role,
          points: member.points, contributed: member.contributed,
          buff: %{xp_mult: buff["xp_mult"], attack_flat: buff["attack_flat"], hp_flat: buff["hp_flat"]},
        }

      nil ->
        nil
    end
  end
end

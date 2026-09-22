defmodule TesIdleWeb.HeroController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, InventoryItem, Item, Location}
  alias TesIdle.Game.{HeroCanon, Origins}
  import Ecto.Query

  def create(conn, params) do
    user = conn.assigns.current_user
    uid = user.id

    existing = Repo.one(from h in Hero, where: h.user_id == ^uid)

    cond do
      existing ->
        conn |> put_status(:bad_request) |> json(%{detail: "Hero already exists"})

      not valid_choice?(params["race"], &HeroCanon.race_key/1) ->
        conn |> put_status(:bad_request) |> json(%{detail: "Unknown race"})

      not valid_choice?(params["hero_class"], &HeroCanon.class_key/1) ->
        conn |> put_status(:bad_request) |> json(%{detail: "Unknown class"})

      true ->
        origin = Origins.resolve(params["origin"])

        if is_nil(origin) do
          conn |> put_status(:bad_request) |> json(%{detail: "Unknown origin"})
        else
          insert_hero(conn, uid, params, origin)
        end
    end
  end

  defp insert_hero(conn, uid, params, origin_key) do
    origin = Origins.get(origin_key)

    case location_by_name(origin.city) do
      nil ->
        conn |> put_status(:unprocessable_entity) |> json(%{detail: "Origin location missing"})

      start_loc ->
        create_at(conn, uid, params, origin_key, origin, start_loc)
    end
  end

  defp create_at(conn, uid, params, origin_key, origin, start_loc) do
    brain_hash = TesIdle.Game.Brain.Genome.brain_hash(uid)
    personality = TesIdle.Game.Personality.generate(params["race"], params["hero_class"], brain_hash: brain_hash)

    hero = %Hero{
      user_id: uid,
      name: params["name"],
      race: params["race"],
      hero_class: params["hero_class"],
      location_id: start_loc.id,
      personality: personality,
      brain_hash: brain_hash,
      skills: origin_skills(origin),
      origin: origin_key,
      dossier: clip_dossier(params["dossier"]),
      gold: origin.gold,
      hunger: origin.hunger,
      mp: Map.get(origin, :mp, 50),
      max_mp: Map.get(origin, :mp, 50)
    }

    case Repo.insert(hero) do
      {:ok, hero} ->
        grant_origin_items(hero, origin.items)
        origin_reputation(hero, origin)
        origin_journal(hero, origin_key)
        json(conn, hero_response(hero))

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> json(%{detail: "Failed"})
    end
  end

  defp origin_skills(%{stealth: value}), do: %{"stealth" => value}
  defp origin_skills(_), do: %{}

  defp origin_reputation(hero, %{reputation: value}) do
    TesIdle.Game.Law.adjust_reputation(hero.id, "храм", value, %{}, hero.name)
  end

  defp origin_reputation(_hero, _origin), do: :ok

  defp valid_choice?(value, resolver) when is_binary(value), do: not is_nil(resolver.(value))
  defp valid_choice?(_, _), do: false

  defp location_by_name(name) do
    Repo.one(from l in Location, where: l.name == ^name, limit: 1)
  end

  defp clip_dossier(nil), do: ""

  defp clip_dossier(text) when is_binary(text) do
    text |> String.trim() |> String.slice(0, 500)
  end

  defp clip_dossier(_), do: ""

  # Нет шаблона — нет строки. Герой уже создан, хроника молчит честно.
  defp origin_journal(hero, origin_key) do
    alias TesIdle.Schemas.NarrativeTemplate

    template =
      Repo.one(
        from t in NarrativeTemplate,
          where: t.template_type == ^"origin_#{origin_key}" and t.is_active == true,
          limit: 1
      )

    if template do
      text =
        template.text_template
        |> String.replace("{hero_name}", hero.name || "")
        |> String.replace("{origin}", TesIdle.Game.Origins.get(origin_key).label)

      Repo.insert(%TesIdle.Schemas.JournalEntry{
        hero_id: hero.id,
        entry_type: "origin_#{origin_key}",
        text: text,
        xp_gained: 0,
        gold_gained: 0
      })
    end
  end

  # Вещь по имени. Нет в каталоге — слот пуст, создание не падает.
  defp grant_origin_items(hero, names) do
    Enum.each(names, fn name ->
      case Repo.one(from i in Item, where: i.name == ^name and i.is_active == true, limit: 1) do
        nil ->
          :ok

        item ->
          Repo.insert!(%InventoryItem{hero_id: hero.id, item_id: item.id, quantity: 1})
      end
    end)
  end

  def me(conn, _params) do
    uid = conn.assigns.current_user.id
    hero = Repo.one(from h in Hero, where: h.user_id == ^uid, preload: [:location, :equipment])

    if hero,
      do: json(conn, hero_response(hero)),
      else: conn |> put_status(:not_found) |> json(%{detail: "No hero"})
  end

  def card(conn, _params) do
    case hero_of(conn) do
      nil ->
        conn |> put_status(:not_found) |> json(%{detail: "No hero"})

      hero ->
        json(conn, card_payload(hero))
    end
  end

  def buy_passive(conn, %{"node" => node}) do
    case hero_of(conn) do
      nil ->
        conn |> put_status(:not_found) |> json(%{detail: "No hero"})

      hero ->
        case TesIdle.Game.Passives.buy(hero, node) do
          {:ok, passives, cost} ->
            hero =
              hero
              |> Ecto.Changeset.change(%{passives: passives, soul_sparks: hero.soul_sparks - cost})
              |> Repo.update!()

            json(conn, %{soul_sparks: hero.soul_sparks, passives: TesIdle.Game.Passives.ranks(hero)})

          {:error, reason} ->
            conn |> put_status(:conflict) |> json(%{detail: Atom.to_string(reason)})
        end
    end
  end

  def update_dossier(conn, params) do
    text = params["dossier"] || ""

    cond do
      not is_binary(text) or String.length(String.trim(text)) > 500 ->
        conn |> put_status(:bad_request) |> json(%{detail: "too_long"})

      is_nil(hero_of(conn)) ->
        conn |> put_status(:not_found) |> json(%{detail: "No hero"})

      true ->
        hero = hero_of(conn)
        trimmed = String.trim(text)

        cond do
          trimmed == (hero.dossier || "") ->
            json(conn, %{dossier: hero.dossier || "", soul_sparks: hero.soul_sparks, cost: 0})

          hero.soul_sparks < 1 ->
            conn |> put_status(:conflict) |> json(%{detail: "not_enough_sparks"})

          true ->
            hero =
              hero
              |> Ecto.Changeset.change(%{dossier: trimmed, soul_sparks: hero.soul_sparks - 1})
              |> Repo.update!()

            json(conn, %{dossier: hero.dossier, soul_sparks: hero.soul_sparks, cost: 1})
        end
    end
  end

  defp hero_of(conn) do
    uid = conn.assigns.current_user.id
    Repo.one(from h in Hero, where: h.user_id == ^uid, preload: [:location])
  end

  defp card_payload(hero) do
    bonus = TesIdle.Game.Passives.bonus(hero)

    %{
      hero: hero_response(hero),
      tree: TesIdle.Game.Passives.tree(hero.hero_class),
      ranks: TesIdle.Game.Passives.ranks(hero),
      costs: costs_for(hero),
      bonus: bonus,
      skills: TesIdle.Game.Skills.all(hero),
      personality: hero.personality || %{}
    }
  end

  defp costs_for(hero) do
    hero.hero_class
    |> TesIdle.Game.Passives.tree()
    |> Map.new(fn node -> {node.id, TesIdle.Game.Passives.next_cost(hero, node.id)} end)
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
      id: p.id,
      species: p.species,
      name: p.name,
      mood: p.mood,
      hunger: p.hunger,
      loyalty: p.loyalty,
      status: p.status,
      revive_at: p.revive_at,
      created_at: p.created_at
    }
  end

  def heartbeat(conn, _params) do
    uid = conn.assigns.current_user.id
    hero = Repo.one(from h in Hero, where: h.user_id == ^uid)

    if hero do
      hero
      |> Hero.changeset(%{last_activity: DateTime.utc_now(), is_online: true})
      |> Repo.update!()

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

      traits =
        TesIdle.Game.Personality.normalize(hero.personality)
        |> Enum.map(fn {t, v} ->
          %{
            "trait" => Atom.to_string(t),
            "value" => v,
            "base" => if(legacy?, do: nil, else: Map.get(genome.traits, t))
          }
        end)

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
          name: hero.name
        }
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
      id: hero.id,
      name: hero.name,
      race: hero.race,
      hero_class: hero.hero_class,
      origin: hero.origin,
      origin_label: origin_label(hero.origin),
      dossier: hero.dossier || "",
      soul_sparks: hero.soul_sparks || 0,
      level: hero.level,
      hp: hero.hp,
      max_hp: hero.max_hp,
      mp: hero.mp,
      max_mp: hero.max_mp,
      sp: hero.sp,
      max_sp: hero.max_sp,
      attack: hero.attack,
      defense: hero.defense,
      xp: hero.xp,
      xp_to_next: hero.xp_to_next,
      gold: hero.gold,
      state: hero.state,
      mood: hero.mood,
      hunger: hero.hunger,
      fatigue: hero.fatigue,
      morale: hero.morale,
      soul_energy: hero.soul_energy,
      game_hour: hero.game_hour,
      game_day: hero.game_day,
      game_era: hero.game_era,
      total_play_time_seconds: hero.total_play_time_seconds,
      total_gold_earned: hero.total_gold_earned,
      total_kills: hero.total_kills,
      is_online: hero.is_online,
      state_data: hero.state_data,
      personality: hero.personality,
      mood_history: mood_list(hero.mood_history),
      skills: TesIdle.Game.Skills.all(hero),
      activity: activity_block(hero),
      pets: pets,
      bounty: TesIdle.Game.Law.total_bounty(hero),
      guild: guild_block,
      location:
        if(hero.location,
          do: %{
            id: hero.location.id,
            name: hero.location.name,
            region: hero.location.region,
            location_type: hero.location.location_type,
            has_shop: hero.location.has_shop,
            has_inn: hero.location.has_inn,
            weather: hero.location.weather,
            danger_level: hero.location.danger_level,
            min_level: hero.location.min_level,
            max_level: hero.location.max_level
          }
        )
    }
  end

  # Единый публичный progress текущего многотикового занятия.
  # Пока legacy-блоки живут в state_data, API нормализует их без дополнительной записи.
  defp activity_block(hero) do
    state_data =
      case Jason.decode(hero.state_data || "{}") do
        {:ok, data} when is_map(data) -> data
        _ -> %{}
      end

    cond do
      is_map(state_data["activity"]) -> state_data["activity"]
      is_map(state_data["fishing"]) -> normalize_activity("fishing", state_data["fishing"])
      is_map(state_data["travel"]) -> normalize_activity("traveling", state_data["travel"])
      is_map(state_data["jail"]) -> normalize_activity("jailed", state_data["jail"])
      true -> nil
    end
  end

  defp normalize_activity(kind, block) do
    total = block["total_ticks"] || block["total"] || block["ticks_left"] || 1
    left = block["ticks_left"] || 0

    %{
      kind: kind,
      phase: block["phase"] || "in_progress",
      ticks_left: left,
      total_ticks: total,
      ticks_done: max(0, total - left),
      target_name: block["destination_name"]
    }
  end

  defp mood_list(nil), do: []

  defp mood_list(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  defp mood_list(value) when is_list(value), do: value
  defp mood_list(_), do: []

  defp origin_label(nil), do: nil
  defp origin_label(key), do: get_in(TesIdle.Game.Origins.get(key), [:label])

  defp guild_block(user_id) do
    case TesIdle.Game.Guilds.membership(user_id) do
      {guild, member} ->
        buff = TesIdle.Game.Guilds.buff_for(guild.level, TesIdle.Game.Guilds.cfg(%{}))

        %{
          id: guild.id,
          name: guild.name,
          emblem: guild.emblem,
          level: guild.level,
          role: member.role,
          points: member.points,
          contributed: member.contributed,
          buff: %{
            xp_mult: buff["xp_mult"],
            attack_flat: buff["attack_flat"],
            hp_flat: buff["hp_flat"]
          }
        }

      nil ->
        nil
    end
  end
end

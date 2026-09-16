defmodule TesIdle.Game.Law do
  @moduledoc """
  LawSystem (ROADMAP Часть II, A-3): преступления, свидетели, награда за голову,
  арест и тюрьма.

  Решения пользователя (binding):
  - **награда за голову — per-city**: state_data["law"]["bounties"][location_id];
  - **репутация — per-faction**: существующая схема `reputations`
    (фракция берётся из конфига law.factions_by_region по региону локации).

  Награды — ЧИСТЫЕ функции над map: экшен кладёт обновлённый "law" в
  result.state_data_update, FSM мержит, пайплайн сохраняет один раз
  (никаких прямых записей state_data — иначе гонка писателей).
  """

  alias TesIdle.Repo
  alias TesIdle.Game.Skills
  alias TesIdle.Schemas.Reputation
  import Ecto.Query

  # --- Чтение ---------------------------------------------------------------

  @doc "Карта наград: location_id → золото (из state_data героя)."
  def bounties(hero) do
    (law_of(hero)["bounties"] || %{})
  end

  @doc "Суммарная награда за голову (для бейджа «в розыске» и осторожности)."
  def total_bounty(hero) do
    hero |> bounties() |> Map.values() |> Enum.sum()
  end

  @doc "Текущий law-блок из state_data (или пустой)."
  def law_of(hero) do
    case Jason.decode(hero.state_data || "{}") do
      {:ok, %{"law" => law}} when is_map(law) -> law
      _ -> %{"bounties" => %{}}
    end
  end

  @doc "Чисто: добавить награду за голову в конкретном городе."
  def add_bounty(law, location_id, amount) when is_number(amount) and amount > 0 do
    key = to_string(location_id || "unknown")
    bounties = law["bounties"] || %{}
    Map.put(law, "bounties", Map.put(bounties, key, (bounties[key] || 0) + round(amount)))
  end

  @doc "Чисто: очистить награды (отсидел/заплатил) — по месту или все."
  def clear_bounties(law, location_id \\ :all) do
    case location_id do
      :all -> Map.put(law, "bounties", %{})
      id -> Map.put(law, "bounties", Map.delete(law["bounties"] || %{}, to_string(id)))
    end
  end

  # --- Преступления ---------------------------------------------------------

  @doc """
  Roll свидетелей: dexterity героя (+ночь, +погода мира, +затмение) vs guard_skill локации.
  Ярмарка в городе — больше глаз: guard усиливается (S-1).
  Возвращает :clean (никто не видел) | :spotted (видели, ушли) | :caught (схватили).
  """
  def witness_roll(ctx) do
    cfg = activities_cfg(ctx)["stealing"] || %{}
    guard = (cfg["guard_skill"] || 30) * guard_factor(ctx.location_type) * fair_guard_mult(ctx)
    dexterity = personality_dex(ctx)

    # Ночь, погода ядра мира и затмение помогают скрытности
    night = ctx.hour >= 22.0 or ctx.hour < 6.0
    night_bonus = if night, do: cfg["night_bonus"] || 0.15, else: 0.0
    weather_bonus = TesIdle.World.Weather.stealth_bonus(ctx.weather)
    eclipse_bonus = if TesIdle.World.Events.eclipse_active?(world_events(ctx)), do: cfg["eclipse_bonus"] || 0.25, else: 0.0

    stealth_power = dexterity + Skills.get(ctx.hero, :stealth) + (night_bonus + weather_bonus + eclipse_bonus) * 100
    roll = :rand.uniform() * (stealth_power + guard)

    cond do
      roll < stealth_power * 0.55 -> :clean
      roll < stealth_power -> :spotted
      true -> :caught
    end
  end

  defp world_events(ctx), do: ((is_map(ctx.world) && ctx.world["events"]) || [])

  defp fair_guard_mult(ctx) do
    cfg = activities_cfg(ctx)["stealing"] || %{}
    if fair_here?(ctx), do: cfg["fair_guard_multiplier"] || 1.2, else: 1.0
  end

  defp fair_here?(ctx) do
    loc_id = ctx.location && to_string(ctx.location.id)
    Enum.any?(world_events(ctx), fn e ->
      e["type"] == "fair" and (is_nil(e["location_id"]) or e["location_id"] == loc_id)
    end)
  end

  @doc """
  Последствия преступления. `crime_gold` — ценность украденного.
  `law` — текущий law-блок из ctx.state_data. Возвращает:

      %{outcome, bounty_added, fine, arrested, law}   # law — обновлённый блок
  """
  def on_crime(ctx, crime_gold, law \\ %{}) do
    cfg = activities_cfg(ctx)["stealing"] || %{}
    outcome = witness_roll(ctx)

    case outcome do
      :clean ->
        %{outcome: :clean, bounty_added: 0, fine: 0, arrested: false, law: law}

      :spotted ->
        bounty = rand_in(cfg["bounty_per_crime"] || [15, 40])
        law = add_bounty(law, ctx.location && ctx.location.id, bounty)
        reputation_hit(ctx, cfg)
        %{outcome: :spotted, bounty_added: bounty, fine: 0, arrested: false, law: law}

      :caught ->
        bounty = rand_in(cfg["bounty_per_crime"] || [15, 40])
        law = add_bounty(law, ctx.location && ctx.location.id, bounty)
        reputation_hit(ctx, cfg)
        fine = trunc(max(crime_gold, 10) * (cfg["fine_multiplier"] || 2))

        current_total =
          Map.values(law["bounties"] || %{}) |> Enum.sum()

        arrest? = current_total >= (cfg["arrest_bounty"] || 50)
        %{outcome: :caught, bounty_added: bounty, fine: fine, arrested: arrest?, law: law}
    end
  end

  # --- Тюрьма ---------------------------------------------------------------

  @doc """
  Создать тюремное заключение (state_data["jail"]).
  Режим (serve/bribe/escape) герой выбирает один раз — по характеру —
  внутри JailAction на первом тике.
  """
  def start_jail(ctx, reason \\ "crime") do
    cfg = activities_cfg(ctx)["jail"] || %{}
    ticks = rand_in(cfg["ticks"] || [3, 10])

    %{
      "ticks_left" => ticks,
      "total_ticks" => ticks,
      "reason" => to_string(reason),
      "location_id" => ctx.location && ctx.location.id,
      "location_name" => ctx.location && ctx.location.name,
      "bounty_at_arrest" => Map.values(law_of(ctx.hero)["bounties"] || %{}) |> Enum.sum(),
      "mode" => nil,
    }
  end

  # --- Репутация per-faction -------------------------------------------------

  # Пороги уровней репутации (P-3). Хранятся в game_configs["law"]["reputation"],
  # значения ниже — дефолты, которыми пустой конфиг замещается.
  @rep_defaults %{
    "quest_complete" => 5,
    "monster_kill" => 1,
    "crime" => 10,        # multiplier на rep_loss из activities.stealing
    "fine_paid" => 2,
    "thresholds" => %{
      "hostile" => -50,     # value ≤ -50
      "unfriendly" => -1,   # value < 0
      "neutral" => 25,      # value < 25
      "friendly" => 75,     # value < 75
      "allied" => 100       # value ≥ 75 (до clamp 100)
    }
  }

  @doc "Конфиг репутации: game_configs[\"law\"][\"reputation\"] с дефолтами по недостающим ключам."
  def rep_cfg(configs) do
    base = Map.get((configs || %{})["law"] || %{}, "reputation", %{})
    Map.merge(@rep_defaults, base, fn _k, v1, v2 ->
      if is_map(v1) and is_map(v2), do: Map.merge(v1, v2), else: v2
    end)
  end

  @doc "Уровень по числовому значению (пороги из cfg[\"thresholds\"])."
  def rep_level(value, cfg) do
    th = cfg["thresholds"] || @rep_defaults["thresholds"]
    cond do
      value <= (th["hostile"] || -50) -> "hostile"
      value < 0 -> "unfriendly"
      value < (th["neutral"] || 25) -> "neutral"
      value < (th["friendly"] || 75) -> "friendly"
      true -> "allied"
    end
  end

  @doc """
  Единая точка изменения репутации (P-3): clamp ±100, пересчёт уровня,
  journal-событие `reputation_change` при смене уровня. Возвращает:
      %{value, old_value, old_level, level, changed?}
  """
  def adjust_reputation(hero_id, faction, delta, configs, hero_name \\ nil) when is_number(delta) and delta != 0 do
    cfg = rep_cfg(configs)

    rep = Repo.one(from r in Reputation, where: r.hero_id == ^hero_id and r.faction == ^faction)

    {old_value, rep} =
      if rep do
        {rep.value, rep}
      else
        # Новая строка начинается с 0 и первого дельта-шага
        inserted = Repo.insert!(%Reputation{hero_id: hero_id, faction: faction, value: 0, level: "neutral"})
        {0, inserted}
      end

    new_value = rep |> Ecto.Changeset.change(%{value: clamp_rep(old_value + delta)})
    |> Repo.update!()

    new_level = rep_level(new_value.value, cfg)
    old_level = rep_level(old_value, cfg)
    changed? = old_level != new_level

    rep
    |> Ecto.Changeset.change(%{level: new_level})
    |> Repo.update!()

    if changed? do
      text = rep_change_text(delta, faction, new_level, old_level, hero_name)
      Repo.insert!(%TesIdle.Schemas.JournalEntry{
        hero_id: hero_id,
        entry_type: "reputation_change",
        text: text,
        created_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      })
    end

    %{value: new_value.value, old_value: old_value, old_level: old_level,
      level: new_level, changed?: changed?}
  end

  defp clamp_rep(v), do: max(-100, min(100, v))

  defp rep_change_text(delta, faction, new_level, _old_level, hero_name) do
    hero = hero_name || "Герой"
    level_ru = %{
      "hostile" => "враг фракции", "unfriendly" => "нелюбим фракцией",
      "neutral" => "нейтрален фракции", "friendly" => "дружелюбно принят фракцией",
      "allied" => "союзник фракции",
    }
    direction = if delta > 0, do: "возвысился", else: "опустился"
    "#{hero} #{direction} в глазах «#{faction}»: теперь #{hero} #{Map.get(level_ru, new_level, new_level)} (#{if delta > 0, do: "+", else: ""}#{delta})."
  end

  @doc "Падение репутации фракции региона (преступление). Пишет в таблицу reputations."
  def reputation_hit(ctx, cfg) do
    faction = faction_for(ctx)
    loss = rand_in(cfg["rep_loss"] || [5, 15]) * rep_cfg(ctx.configs)["crime"]
    adjust_reputation(ctx.hero.id, faction, -max(1, div(loss, 10)), ctx.configs, ctx.hero.name)
    loss
  end

  @doc "Фракция, чья юрисдикция над текущей локацией (конфиг region → faction)."
  def faction_for(ctx) do
    cfg = (ctx.configs || %{})["law"] || %{}
    region = if ctx.location, do: ctx.location.region, else: nil
    Map.get(cfg["factions_by_region"] || %{}, region, cfg["default_faction"] || "Империя")
  end

  # --- Служебное --------------------------------------------------------------

  defp personality_dex(ctx), do: Map.get(ctx.personality || %{}, :dexterity, 50)

  defp guard_factor("city"), do: 1.0
  defp guard_factor("village"), do: 0.6
  defp guard_factor(_), do: 0.3

  defp activities_cfg(ctx), do: (ctx.configs || %{})["activities"] || %{}

  defp rand_in([lo, hi]) when is_number(lo) and is_number(hi), do: Enum.random(round(lo)..round(hi))
  defp rand_in(v) when is_number(v), do: v
  defp rand_in(_), do: 20
end

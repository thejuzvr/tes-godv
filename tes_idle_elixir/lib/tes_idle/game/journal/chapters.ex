defmodule TesIdle.Game.Journal.Chapters do
  @moduledoc """
  S-3: главы дневника — дневник как книга жизни героя.

  Граница главы: смена игрового дня ИЛИ переломное событие (война, дракон,
  затмение, волна монстров, арест, новый уровень). Название главы —
  «День N. <фраза>», фраза по перелому или спокойному дню. Числа и фразы —
  в `game_configs["journal"]` (правило: hardcode только в конфигах).
  """

  @doc "Текущая глава из state_data[\"journal\"]. Возвращает {chapter, title}."
  def current(state_data) do
    j = state_data["journal"] || %{}
    {j["chapter"] || 1, j["title"]}
  end

  @doc """
  Проверяет границу главы. Возвращает {chapter, title, journal_state}.
  `breaks` — переломы тика: "world" (новые мир-события), "arrest", "level_up".
  Перелом важнее смены дня (название главы — по перелому).
  """
  def ensure(hero, state_data, ctx, breaks \\ []) do
    cfg = ctx.configs["journal"] || %{}
    j = state_data["journal"] || %{}
    chapter = j["chapter"] || 1

    world_break = if "world" in breaks, do: new_world_break(j, ctx), else: nil
    jail_break? = "arrest" in breaks and Map.get(j, "jail_chapter", 0) != chapter
    level_break? = "level_up" in breaks and Map.get(j, "level_chapter", 0) != chapter
    new_day? = Map.get(j, "chapter_day") != hero.game_day

    cond do
      world_break ->
        title = title_for(cfg, world_break, hero)
        {chapter + 1, title, put_chapter(j, chapter + 1, title, hero, ctx)}

      jail_break? ->
        title = title_for(cfg, "arrest", hero)
        {chapter + 1, title, put_chapter(j, chapter + 1, title, hero, ctx) |> Map.put("jail_chapter", chapter + 1)}

      level_break? ->
        title = title_for(cfg, "level_up", hero)
        {chapter + 1, title, put_chapter(j, chapter + 1, title, hero, ctx) |> Map.put("level_chapter", chapter + 1)}

      new_day? ->
        title = title_for(cfg, "day", hero)
        {chapter + 1, title, put_chapter(j, chapter + 1, title, hero, ctx)}

      true ->
        {chapter, j["title"], j}
    end
  end

  @doc """
  Текст мотива решения из последней записи decision_log (S-2 трасса):
  «heal (0.62) — дракон в небе: осторожный пережидает (−0.12)».
  """
  def motive_for(nil), do: nil
  def motive_for(brain) when is_map(brain) do
    case (brain["decision_log"] || []) |> List.last() do
      nil ->
        nil

      entry ->
        reasons = entry["reasons"] || []
        base = "#{entry["goal"]} (#{entry["utility"] || 0})"

        case Enum.take(reasons, 2) do
          [] -> base
          rs -> "#{base} — #{Enum.join(rs, "; ")}"
        end
    end
  end

  @doc """
  «Новости мира»: если в мире героя активно не-виденное событие из
  news-списка (глобальное или в локации героя) — возвращает
  {event, journal_update} с шансом news_chance, иначе nil.
  """
  def world_news_candidate(hero, state_data, ctx) do
    cfg = ctx.configs["journal"] || %{}
    chance = cfg["news_chance"] || 0.25
    news_types = cfg["news_events"] || ["war_declared", "dragon", "eclipse", "monster_wave", "fair"]

    j = state_data["journal"] || %{}
    seen = j["news_seen"] || []

    events = (if is_map(ctx.world), do: ctx.world["events"], else: nil) || []
    hero_loc = hero.location_id && to_string(hero.location_id)

    candidate =
      Enum.find(events, fn e ->
        e["type"] in news_types and e["id"] not in seen and
          (is_nil(e["location_id"]) or e["location_id"] == hero_loc)
      end)

    if is_map(candidate) and :rand.uniform() < chance do
      seen2 =
        (seen ++ [candidate["id"]])
        |> Enum.uniq()
        |> Enum.take(-20)

      {candidate, Map.put(j, "news_seen", seen2)}
    else
      nil
    end
  end

  # --- Приватное ------------------------------------------------------------

  defp new_world_break(j, ctx) do
    cfg = ctx.configs["journal"] || %{}
    break_types = cfg["break_events"] || ["war_declared", "dragon", "eclipse", "monster_wave"]
    seen = j["break_seen"] || []

    events = (if is_map(ctx.world), do: ctx.world["events"], else: nil) || []
    hero_loc = ctx.location && to_string(ctx.location.id)

    Enum.find(events, fn e ->
      e["type"] in break_types and e["id"] not in seen and
        (is_nil(e["location_id"]) or e["location_id"] == hero_loc)
    end)
    |> case do
      nil -> nil
      e -> e["type"]
    end
  end

  defp put_chapter(j, chapter, title, hero, ctx) do
    cfg = ctx.configs["journal"] || %{}
    break_types = cfg["break_events"] || ["war_declared", "dragon", "eclipse", "monster_wave"]

    events = (if is_map(ctx.world), do: ctx.world["events"], else: nil) || []

    break_seen =
      events
      |> Enum.filter(&(&1["type"] in break_types))
      |> Enum.map(& &1["id"])
      |> Enum.concat(Map.get(j, "break_seen", []))
      |> Enum.uniq()
      |> Enum.take(-20)

    j
    |> Map.merge(%{"chapter" => chapter, "chapter_day" => hero.game_day, "title" => title, "break_seen" => break_seen})
  end

  defp title_for(cfg, kind, hero) do
    titles = cfg["titles"] || %{}
    phrase = titles[kind] || "Тихий день"
    "День #{hero.game_day}. #{phrase}"
  end
end
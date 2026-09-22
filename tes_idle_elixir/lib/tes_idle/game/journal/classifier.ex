defmodule TesIdle.Game.Journal.Classifier do
  @moduledoc """
  Категории событий хроники (docs/JOURNAL_RETENTION_ARCHITECTURE.md, 6.1).

  Ключевой принцип: решение принимается **по семантике результата**, а не
  только по имени типа. `generic_action` нельзя без проверки считать пустым —
  за ним может скрываться победа, находка или смерть.

  Категории:

  - `:milestone` — важная веха, кандидат в долгую память (`hero_milestones`);
  - `:important` — надо показать сразу и не троттлить никогда;
  - `:progress` — обычный прогресс с наградами (опыт/золото/предмет);
  - `:ambient` — атмосферный фон, который можно ограничивать.

  Модуль чистый: никаких Repo-запросов, поэтому правила проверяются
  обычными unit-тестами.
  """

  @type category :: :milestone | :important | :progress | :ambient

  # ─── Типы, которые трогать нельзя ────────────────────
  # Это либо вехи, либо то, о чём игрок обязан узнать немедленно.
  @milestone_types ~w(
    death_respawn hero_created generation_shift
    guild_founded guild_levelup guild_feast
    quest_completed quest_reward
    hero_encounter_meeting hero_encounter_witness
  )

  @important_types ~w(
    hero_victory hero_defeat enemy_ambush death
    discover_treasure find_shrine find_loot rare_loot
    spot_bandits pet_adopted pet_left pet_revived
    gate_closed gate_fallen oblivion_gate
    reputation_change jail escape jail_release
    guild_shop_purchase construction_donation gate_donation
  )

  # Типы, которые считаются фоновыми по своей природе.
  # Всё, чего нет ни здесь, ни выше, тоже считается фоном — но с оговоркой:
  # решение всё равно уточняется семантикой результата (см. classify/3).
  @ambient_types ~w(
    generic_action smell_flowers watch_sunset hear_birds hear_river hear_wolves
    fishing_wait notice_tracks find_tracks rest_by_fire shelter_from_storm
    feel_confident watch_stars count_coins hum_tune idle_thought
    gather_wood fetch_water mend_clothes sharpen_blade
    collect_herbs collect_mushrooms gather_plants pick_flowers
    dream world_news
  )

  # ─── Публичное API ───────────────────────────────────

  @doc "Типы, которые троттлинг не имеет права подавлять."
  def protected_types, do: @milestone_types ++ @important_types

  @doc "Типы, которые считаются атмосферными по своей природе."
  def ambient_types, do: @ambient_types

  @doc """
  Категория события.

  `entry_type` — тип записи; `result` — результат действия (может быть `nil`
  для путей вне Pipeline, например god/guild/encounter). Проверка результата
  идёт первой: атмосферный тип с победой внутри — не атмосфера.
  """
  def classify(entry_type, result \\ nil) do
    cond do
      entry_type in @milestone_types -> :milestone
      entry_type in @important_types -> :important
      semantic_important?(result) -> :important
      semantic_progress?(result) -> :progress
      entry_type in @ambient_types -> :ambient
      # Неизвестный тип — консервативно: не считаем его шумом,
      # чтобы случайно не выбросить новую важную запись.
      true -> :progress
    end
  end

  @doc "Атмосферное ли событие (единственная категория, которую можно подавлять)."
  def throttleable?(entry_type, result \\ nil), do: classify(entry_type, result) == :ambient

  @doc """
  Является ли событие кандидатом в памятную веху по результату.
  Не все победы — вехи: вехой становится первая победа над монстром или
  новый личный рекорд уровня, а не каждый бой.
  """
  def milestone_candidate(entry_type, result) do
    cond do
      entry_type == "death_respawn" -> :generation_shift
      entry_type in ~w(quest_completed quest_reward) -> :quest_completed
      entry_type == "guild_founded" -> :guild_joined
      level_up?(result) -> :level_threshold
      first_kill?(result) -> :first_kill
      rare_loot?(result) -> :rare_loot
      true -> nil
    end
  end

  # ─── Семантика результата ────────────────────────────

  # Победа/поражение/смерть/квест/уникальная находка — всегда важно,
  # каким бы «фоновым» ни был тип записи.
  defp semantic_important?(nil), do: false

  defp semantic_important?(result) when is_map(result) do
    combat = result[:combat_result] || result["combat_result"] || %{}

    victory?(combat) or
      hero_defeated?(combat) or
      result[:death] == true or
      result[:quest_complete] == true or
      result[:quest_completed] == true or
      result[:quest_done] == true or
      rare_loot?(result) or
      result[:escaped] == true
  end

  defp semantic_important?(_), do: false

  defp victory?(combat) when is_map(combat) do
    combat[:victory] == true or combat["victory"] == true
  end

  defp victory?(_), do: false

  defp semantic_progress?(nil), do: false

  defp semantic_progress?(result) when is_map(result) do
    (result[:xp] || 0) > 0 or
      (result[:gold_change] || 0) > 0 or
      (result[:item_gained] || result["item_gained"]) != nil or
      result[:combat_result] != nil
  end

  defp semantic_progress?(_), do: false

  defp hero_defeated?(combat) when is_map(combat) do
    combat[:hero_defeated] == true or combat["hero_defeated"] == true
  end

  defp hero_defeated?(_), do: false

  defp level_up?(result) when is_map(result) do
    result[:level_up] == true or (result[:levels_gained] || 0) > 0
  end

  defp level_up?(_), do: false

  defp first_kill?(result) when is_map(result) do
    result[:first_kill] == true
  end

  defp first_kill?(_), do: false

  @rare_rarities ~w(rare epic legendary)

  defp rare_loot?(result) when is_map(result) do
    rarity = result[:rarity] || result["rarity"]

    (is_binary(rarity) and rarity in @rare_rarities) or result[:rare_loot] == true
  end

  defp rare_loot?(_), do: false

  @doc "Человекочитаемое имя категории — для отчётов и UI."
  def category_label(:milestone), do: "веха"
  def category_label(:important), do: "важное"
  def category_label(:progress), do: "прогресс"
  def category_label(:ambient), do: "атмосфера"
  def category_label(_), do: "неизвестно"
end

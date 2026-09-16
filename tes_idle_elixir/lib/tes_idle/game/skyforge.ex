defmodule TesIdle.Game.Skyforge do
  @moduledoc """
  C-2 «Небесная кузня» (Skyforge в Вайтране): личный бесконечный сток золота.

  Заточка предмета экипировки: платит золото → слот получает +1 уровень заточки.
  Прибавка плоская: weapon/amulet — +1 attack за уровень, прочие — +1 defense.
  Цена следующего уровня — `round(base_cost × level^growth)` (50 × 1^1.8 = 50 … 10 → ~3150).
  Конфиг — `game_configs["skyforge"]`: base_cost/growth/cap/fail_chance (дефолты — fallback/1).
  Золото уходит в никуда (самый чистый сток). Журнал — шаблон `enhance_success` из БД
  (нет шаблона — записи нет, честно).
  """

  import Ecto.Query
  alias Ecto.Multi
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Equipment, Item, Sharpening}

  @slots [:weapon, :head, :body, :legs, :ring, :amulet]
  @slot_names ["weapon", "head", "body", "legs", "ring", "amulet"]
  @attack_slots [:weapon, :amulet]

  def default_config do
    %{"base_cost" => 50, "growth" => 1.8, "cap" => 10, "fail_chance" => 0}
  end

  def cfg(configs) do
    Map.get(configs, "skyforge") || default_config()
  end

  @doc "Цена перехода на уровень level (1..cap): round(base × level^growth)."
  def price(level, cfg) do
    base = cfg["base_cost"] || 50
    growth = cfg["growth"] || 1.8
    round(base * :math.pow(level, growth))
  end

  @doc "Уровень заточки предмета героя (0 если не точили)."
  def level_for(hero_id, item_id) do
    Repo.one(from s in Sharpening, where: s.hero_id == ^hero_id and s.item_id == ^item_id, select: s.level) || 0
  end

  @doc "Карта уровней заточки героя: %{item_id => level}."
  def levels_for_hero(hero_id) do
    from(s in Sharpening, where: s.hero_id == ^hero_id, select: {s.item_id, s.level})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Заточка слота: item в слоте → level < cap → золото >= цена → списание + level+1.
  Возвращает {:ok, %{item, level, price, gold_left}} | {:error, reason}.
  """
  def enhance(_user, hero, slot, configs) when is_binary(slot) do
    cfg = cfg(configs)
    cap = cfg["cap"] || 10

    case Repo.one(from e in Equipment, where: e.hero_id == ^hero.id, limit: 1) do
      nil ->
        {:error, :empty_slot}

      equipment ->
        item_id = if slot in @slot_names, do: Map.get(equipment, :"#{slot}_id"), else: nil

        cond do
          item_id == nil ->
            {:error, :empty_slot}

          true ->
            item = Repo.get!(Item, item_id)
            current = level_for(hero.id, item_id)

            cond do
              current >= cap ->
                {:error, :cap_reached}

              true ->
                cost = price(current + 1, cfg)

                cond do
                  hero.gold < cost ->
                    {:error, :not_enough_gold}

                  true ->
                    do_enhance(hero, item, current, cost)
                end
            end
        end
    end
  end

  def enhance(_user, _hero, _slot, _configs), do: {:error, :bad_slot}

  defp do_enhance(hero, item, current, cost) do
    sharpening =
      Repo.one(from s in Sharpening, where: s.hero_id == ^hero.id and s.item_id == ^item.id, limit: 1)

    new_level = current + 1

    multi =
      Multi.new()
      |> Multi.update(:hero, Ecto.Changeset.change(hero, gold: hero.gold - cost))
      |> Multi.insert_or_update(:sharpening, fn _ ->
        if sharpening do
          Ecto.Changeset.change(sharpening, level: new_level)
        else
          Sharpening.changeset(%Sharpening{}, %{hero_id: hero.id, item_id: item.id, level: new_level})
        end
      end)

    case Repo.transaction(multi) do
      {:ok, %{hero: updated}} ->
        journal_enhance(hero, item, new_level)
        {:ok, %{item: item, level: new_level, price: cost, gold_left: updated.gold}}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  # Прибавка заточки к слоту: weapon/amulet — attack, прочие — defense
  def bonus_for_slot(slot_atom, level) do
    if slot_atom in @attack_slots, do: {level, 0}, else: {0, level}
  end

  @doc "Суммарный бонус заточки по надетым слотам equipment: {attack, defense}."
  def equipment_bonus(equipment) when is_struct(equipment, Equipment) do
    levels = levels_for_hero(equipment.hero_id)

    Enum.reduce(@slots, {0, 0}, fn slot, {atk, dfn} ->
      item_id = Map.get(equipment, :"#{slot}_id")

      level =
        if item_id do
          Map.get(levels, item_id) || 0
        else
          0
        end

      {b_atk, b_dfn} = bonus_for_slot(slot, level)
      {atk + b_atk, dfn + b_dfn}
    end)
  end

  def equipment_bonus(nil), do: {0, 0}

  # Журнал — только из БД: шаблон enhance_success (нет шаблона — записи нет)
  defp journal_enhance(hero, item, new_level) do
    template =
      Repo.one(
        from t in TesIdle.Schemas.NarrativeTemplate,
          where: t.template_type == "enhance_success" and t.is_active == true,
          order_by: fragment("random()"),
          limit: 1,
          select: t.text_template
      )

    if template do
      text =
        TesIdle.Game.Narrative.TemplateEngine.render_vars(template, %{
          "hero_name" => hero.name,
          "item" => item.name,
          "level" => Integer.to_string(new_level)
        })

      Repo.insert!(%TesIdle.Schemas.JournalEntry{
        hero_id: hero.id,
        entry_type: "enhance_success",
        text: text,
        created_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })
    end

    :ok
  rescue
    _ -> :ok
  end
end

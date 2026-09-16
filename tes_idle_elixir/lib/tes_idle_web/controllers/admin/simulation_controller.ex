defmodule TesIdleWeb.Admin.SimulationController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Item, Location, Monster}
  import Ecto.Query

  @monster_names [
    "Лесной волк", "Скевер", "Грязекраб", "Разбойник", "Драугр-воин",
    "Снежный медведь", "Саблезуб", "Морозный паук", "Фалмер",
    "Одичавший пёс", "Бандит-лучник", "Каменевый голем",
  ]

  @consumable_names [
    {"Яблоко", "🍎"}, {"Круг хлеба", "🍞"}, {"Кружка эля", "🍺"},
    {"Зелье лечения", "🧪"}, {"Похлёбка из лука-порея", "🍲"},
    {"Сырная головка", "🧀"}, {"Медовое пирожное", "🍯"},
  ]

  @equipment_names [
    {"Железный меч", "weapon", "⚔️"}, {"Стальной кинжал", "weapon", "🗡️"},
    {"Кожаный шлем", "head", "⛑️"}, {"Железный шлем", "head", "⛑️"},
    {"Кожаный доспех", "body", "🥋"}, {"Кольчуга", "body", "🥋"},
    {"Кожаные сапоги", "legs", "🥾"}, {"Серебряное кольцо", "ring", "💍"},
    {"Амулет Стендарра", "amulet", "📿"},
  ]

  @junk_names [
    {"Треснувший черепок", "🥣"}, {"Ржавая ложка", "🥄"},
    {"Старая кружка", "🥛"}, {"Кучка веток", "🌿"}, {"Неизвестная кость", "🦴"},
  ]

  def run(conn, params) do
    ticks = parse_count(params, 300)
    json(conn, %{message: "Simulation started", ticks: ticks, status: "running"})
  end

  def generate_monsters(conn, params) do
    count = parse_count(params, 5)

    location_ids = Repo.all(from l in Location, select: l.id)

    if location_ids == [] do
      conn |> put_status(:bad_request) |> json(%{detail: "No locations in DB — seed first"})
    else
      monsters =
        Enum.map(1..count, fn _ ->
          {:ok, monster} =
            Repo.insert(%Monster{
              name: Enum.random(@monster_names),
              description: "Сгенерировано админ-симуляцией",
              min_level: 1,
              max_level: Enum.random(3..8),
              hp: 20 + :rand.uniform(60),
              attack_min: 3 + :rand.uniform(5),
              attack_max: 8 + :rand.uniform(10),
              defense: :rand.uniform(5),
              xp_reward: 15 + :rand.uniform(30),
              gold_min: 5,
              gold_max: 15 + :rand.uniform(30),
              is_active: true,
              location_id: Enum.random(location_ids),
            })

          %{id: monster.id, name: monster.name, location_id: monster.location_id}
        end)

      json(conn, %{message: "Generated #{count} monsters", count: count, monsters: monsters})
    end
  end

  def generate_items(conn, params) do
    count = parse_count(params, 10)

    items =
      Enum.map(1..count, fn _ ->
        roll = :rand.uniform(10)

        attrs =
          cond do
            roll <= 4 -> random_consumable()
            roll <= 8 -> random_equipment()
            true -> random_junk()
          end

        {:ok, item} = Repo.insert(Item.changeset(%Item{}, attrs))
        %{id: item.id, name: item.name, type: item.item_type, rarity: item.rarity}
      end)

    json(conn, %{message: "Generated #{count} items", count: count, items: items})
  end

  def generate_all(conn, _params) do
    monsters = generate_monsters_data(5)
    items = generate_items_data(10)

    json(conn, %{
      message: "Generated #{length(monsters)} monsters and #{length(items)} items",
      monsters: monsters,
      items: items,
      narratives: %{status: "skipped", reason: "LLM narrative generation is not implemented in the Elixir port"},
    })
  end

  def generate_narratives_moderated(conn, _params) do
    conn
    |> put_status(:not_implemented)
    |> json(%{detail: "LLM narrative generation is not implemented in the Elixir port yet"})
  end

  # ─── Helpers ─────────────────────────────────────────

  defp generate_monsters_data(count) do
    location_ids = Repo.all(from l in Location, select: l.id)

    if location_ids == [] do
      []
    else
      Enum.map(1..count, fn _ ->
        {:ok, monster} =
          Repo.insert(%Monster{
            name: Enum.random(@monster_names),
            description: "Сгенерировано админ-симуляцией",
            min_level: 1,
            max_level: Enum.random(3..8),
            hp: 20 + :rand.uniform(60),
            attack_min: 3 + :rand.uniform(5),
            attack_max: 8 + :rand.uniform(10),
            defense: :rand.uniform(5),
            xp_reward: 15 + :rand.uniform(30),
            gold_min: 5,
            gold_max: 15 + :rand.uniform(30),
            is_active: true,
            location_id: Enum.random(location_ids),
          })

        %{id: monster.id, name: monster.name, location_id: monster.location_id}
      end)
    end
  end

  defp generate_items_data(count) do
    Enum.map(1..count, fn _ ->
      roll = :rand.uniform(10)

      attrs =
        cond do
          roll <= 4 -> random_consumable()
          roll <= 8 -> random_equipment()
          true -> random_junk()
        end

      {:ok, item} = Repo.insert(Item.changeset(%Item{}, attrs))
      %{id: item.id, name: item.name, type: item.item_type, rarity: item.rarity}
    end)
  end

  defp random_consumable do
    {name, icon} = Enum.random(@consumable_names)

    %{
      name: name,
      description: "Сгенерировано админ-симуляцией",
      item_type: "consumable",
      rarity: weighted_rarity(),
      icon: icon,
      weight: 0.1 + :rand.uniform(9) / 10,
      sell_price: 2 + :rand.uniform(8),
      heal_hp: 5 + :rand.uniform(20),
      reduce_hunger: 10.0 + :rand.uniform(20),
      boost_morale: :rand.uniform(10) * 1.0,
    }
  end

  defp random_equipment do
    {name, slot, icon} = Enum.random(@equipment_names)

    %{
      name: name,
      description: "Сгенерировано админ-симуляцией",
      item_type: "equipment",
      rarity: weighted_rarity(),
      icon: icon,
      weight: 1.0 + :rand.uniform(70) / 10,
      sell_price: 10 + :rand.uniform(40),
      equip_slot: slot,
      attack_bonus: if(slot == "weapon", do: 1 + :rand.uniform(7), else: 0),
      defense_bonus: if(slot in ["head", "body", "legs"], do: 1 + :rand.uniform(6), else: :rand.uniform(2)),
      hp_bonus: :rand.uniform(10),
    }
  end

  defp random_junk do
    {name, icon} = Enum.random(@junk_names)

    %{
      name: name,
      description: "Сгенерировано админ-симуляцией",
      item_type: "junk",
      rarity: "common",
      icon: icon,
      weight: 0.5 + :rand.uniform(15) / 10,
      sell_price: 1,
    }
  end

  defp weighted_rarity do
    roll = :rand.uniform(100)

    cond do
      roll <= 60 -> "common"
      roll <= 85 -> "uncommon"
      roll <= 97 -> "rare"
      true -> "epic"
    end
  end

  defp parse_count(params, default) do
    case Integer.parse(Map.get(params, "count", "") || "") do
      {n, _} when n > 0 -> min(n, 100)
      _ -> default
    end
  end
end

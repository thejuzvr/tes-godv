defmodule TesIdle.Game.Passives do
  @moduledoc """
  Пассивы игрока (docs/PLAN_CHARACTER.md, раздел 4).

  Не путать с `Game.Skills`: ремесло растёт от дел героя само, пассив
  покупает игрок за искры. Тик это поле не меняет.

  У каждого класса три ветки по четыре узла, у узла три ранга.
  Класс открывает первый узел своей ветки бесплатно — это не покупка.
  """

  alias TesIdle.Game.HeroCanon

  @ranks 3
  @rank_cost %{1 => 1, 2 => 2, 3 => 4}

  # Общие ветки есть у всех. Третья зависит от класса.
  @common [:steel, :trail]

  @branch_for %{
    "warrior" => :steel,
    "mage" => :sign,
    "thief" => :shadow,
    "rogue" => :shadow,
    "hunter" => :trail,
    "priest" => :name,
    "paladin" => :steel,
    "assassin" => :shadow
  }

  # Скидка класса: цена ранга в своей ветке на 1 искру ниже, но не ниже 1.
  @discount %{"rogue" => :shadow, "paladin" => :steel}

  # Узел открыт классом сразу в ранг 1, искр не стоит.
  @granted %{
    "warrior" => "steel_1",
    "mage" => "sign_1",
    "thief" => "shadow_1",
    "hunter" => "trail_1",
    "priest" => "name_1",
    "assassin" => "shadow_1"
  }

  @nodes %{
    "steel_1" => %{branch: :steel, order: 1, label: "Закалка"},
    "steel_2" => %{branch: :steel, order: 2, label: "Стойка"},
    "steel_3" => %{branch: :steel, order: 3, label: "Пластины"},
    "steel_4" => %{branch: :steel, order: 4, label: "Крепость"},
    "trail_1" => %{branch: :trail, order: 1, label: "Шаг"},
    "trail_2" => %{branch: :trail, order: 2, label: "Привал"},
    "trail_3" => %{branch: :trail, order: 3, label: "Сноровка"},
    "trail_4" => %{branch: :trail, order: 4, label: "Дорога"},
    "shadow_1" => %{branch: :shadow, order: 1, label: "Шаг в сторону"},
    "shadow_2" => %{branch: :shadow, order: 2, label: "Тишина"},
    "shadow_3" => %{branch: :shadow, order: 3, label: "Чутьё"},
    "shadow_4" => %{branch: :shadow, order: 4, label: "Исчезновение"},
    "name_1" => %{branch: :name, order: 1, label: "Слово"},
    "name_2" => %{branch: :name, order: 2, label: "Обет"},
    "name_3" => %{branch: :name, order: 3, label: "Милость"},
    "name_4" => %{branch: :name, order: 4, label: "Имя"},
    "sign_1" => %{branch: :sign, order: 1, label: "Искра знака"},
    "sign_2" => %{branch: :sign, order: 2, label: "Ровная рука"},
    "sign_3" => %{branch: :sign, order: 3, label: "Запас"},
    "sign_4" => %{branch: :sign, order: 4, label: "Знак"}
  }

  def nodes, do: @nodes
  def max_rank, do: @ranks

  @doc "Три ветки героя: две общие и одна по классу."
  def branches(hero_class) do
    key = HeroCanon.class_key(hero_class)
    own = Map.get(@branch_for, key, :steel)
    Enum.uniq(@common ++ [own])
  end

  @doc "Узлы веток героя по порядку."
  def tree(hero_class) do
    allowed = branches(hero_class) |> Enum.map(&to_string/1)

    @nodes
    |> Enum.filter(fn {_id, node} -> to_string(node.branch) in allowed end)
    |> Enum.sort_by(fn {_id, node} -> {node.branch, node.order} end)
    |> Enum.map(fn {id, node} -> Map.put(node, :id, id) end)
  end

  @doc "Ранги с учётом бесплатного узла класса. Покупка пишется поверх."
  def ranks(hero) do
    bought = normalize(hero.passives)
    granted = granted_node(hero.hero_class)

    base = if granted, do: Map.put(%{}, granted, 1), else: %{}
    Map.merge(base, bought)
  end

  def rank(hero, node_id), do: Map.get(ranks(hero), node_id, 0)

  @doc "Цена следующего ранга. `nil`, если узел чужой, закрыт или уже на пределе."
  def next_cost(hero, node_id) do
    with %{order: order, branch: branch} <- Map.get(@nodes, node_id),
         true <- to_string(branch) in Enum.map(branches(hero.hero_class), &to_string/1),
         current when current < @ranks <- rank(hero, node_id),
         true <- order == 1 or rank(hero, previous(node_id)) >= 1 do
      cost(@rank_cost[current + 1], hero.hero_class, branch)
    else
      _ -> nil
    end
  end

  @doc """
  Покупка следующего ранга.

  Возвращает `{:ok, passives, cost}` либо
  `{:error, :unknown | :locked | :max_rank | :not_enough_sparks}`.
  Поле героя не пишет: это делает контроллер.
  """
  def buy(hero, node_id) do
    cond do
      not Map.has_key?(@nodes, node_id) or to_string(@nodes[node_id].branch) not in Enum.map(branches(hero.hero_class), &to_string/1) ->
        {:error, :unknown}

      rank(hero, node_id) >= @ranks ->
        {:error, :max_rank}

      is_nil(next_cost(hero, node_id)) ->
        {:error, :locked}

      hero.soul_sparks < next_cost(hero, node_id) ->
        {:error, :not_enough_sparks}

      true ->
        cost = next_cost(hero, node_id)
        current = rank(hero, node_id)
        {:ok, Map.put(normalize(hero.passives), node_id, current + 1), cost}
    end
  end

  @doc """
  Плоский бонус для точек, где он уже считается.

  `hp` и `defense` читает бой, `rest` — лечение, `skill` — темп ремесла (доля),
  `fatigue` — сколько усталости снимает дорога, `reputation` — доля к приросту.
  Полный ранг ветки не умножает опыт и золото.
  """
  def bonus(hero) do
    ranks = ranks(hero)

    %{
      hp: sum(ranks, ~w(steel_1 steel_3), 4),
      defense: sum(ranks, ~w(steel_2 steel_4), 1),
      rest: sum(ranks, ~w(name_3 trail_2), 2),
      skill: sum(ranks, ~w(trail_3 trail_4 sign_2), 1) / 100,
      fatigue: sum(ranks, ~w(trail_1), 1),
      reputation: sum(ranks, ~w(name_1 name_2 name_4), 2) / 100,
      mp: sum(ranks, ~w(sign_1 sign_3 sign_4), 3),
      stealth: sum(ranks, ~w(shadow_1 shadow_2 shadow_3 shadow_4), 2)
    }
  end

  # ─── Внутреннее ──────────────────────────────────────

  defp granted_node(hero_class), do: Map.get(@granted, HeroCanon.class_key(hero_class))

  defp previous(node_id) do
    [branch, order] = String.split(node_id, "_")
    "#{branch}_#{String.to_integer(order) - 1}"
  end

  defp cost(price, hero_class, branch) do
    key = HeroCanon.class_key(hero_class)
    if Map.get(@discount, key) == branch, do: max(1, price - 1), else: price
  end

  defp sum(ranks, ids, per_rank) do
    ids
    |> Enum.map(&Map.get(ranks, &1, 0))
    |> Enum.sum()
    |> Kernel.*(per_rank)
  end

  defp normalize(nil), do: %{}

  defp normalize(passives) when is_map(passives) do
    Map.new(passives, fn {key, value} -> {to_string(key), clamp_rank(value)} end)
  end

  defp normalize(_), do: %{}

  defp clamp_rank(value) when is_integer(value), do: value |> max(0) |> min(@ranks)
  defp clamp_rank(value) when is_float(value), do: value |> trunc() |> clamp_rank()
  defp clamp_rank(_), do: 0
end

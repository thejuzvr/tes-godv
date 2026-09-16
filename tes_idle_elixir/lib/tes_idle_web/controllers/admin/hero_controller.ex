defmodule TesIdleWeb.Admin.HeroController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.Hero
  import Ecto.Query

  def index(conn, params) do
    page = Map.get(params, "page", "1") |> String.to_integer()
    per_page = Map.get(params, "per_page", "20") |> String.to_integer() |> min(100)
    offset = (page - 1) * per_page

    total = Repo.one(from h in Hero, select: count(h.id))
    heroes = Repo.all(from h in Hero, limit: ^per_page, offset: ^offset, order_by: h.name)

    json(conn, %{
      heroes: Enum.map(heroes, fn h ->
        %{id: h.id, name: h.name, level: h.level, state: h.state, hp: h.hp, max_hp: h.max_hp,
          gold: h.gold, total_kills: h.total_kills}
      end),
      total: total,
      page: page,
      per_page: per_page,
    })
  end

  def show(conn, %{"id" => id}) do
    hero = Repo.get(Hero, id)
    if !hero, do: conn |> put_status(:not_found) |> json(%{detail: "Hero not found"}) |> halt()

    json(conn, %{
      hero: %{id: hero.id, name: hero.name, race: hero.race, hero_class: hero.hero_class,
        level: hero.level, hp: hero.hp, max_hp: hero.max_hp, xp: hero.xp, xp_to_next: hero.xp_to_next,
        gold: hero.gold, state: hero.state, mood: hero.mood, attack: hero.attack, defense: hero.defense},
      recent_journal: [],
    })
  end

  def reset(conn, %{"id" => id}) do
    hero = Repo.get(Hero, id)
    if !hero, do: conn |> put_status(:not_found) |> json(%{detail: "Hero not found"}) |> halt()

    Repo.update!(Hero.changeset(hero, %{
      level: 1, hp: 100, max_hp: 100, mp: 50, max_mp: 50,
      sp: 100, max_sp: 100, attack: 10, defense: 5,
      xp: 0, xp_to_next: 100, gold: 0, state: "exploring",
    }))

    json(conn, %{message: "Hero reset"})
  end

  def delete(conn, %{"id" => id}) do
    hero = Repo.get(Hero, id)
    if !hero, do: conn |> put_status(:not_found) |> json(%{detail: "Hero not found"}) |> halt()

    # Delete related records first (FK constraints)
    alias TesIdle.Schemas.{InventoryItem, Equipment, JournalEntry, ActiveQuest, Reputation}
    from(i in InventoryItem, where: i.hero_id == ^id) |> Repo.delete_all()
    from(e in Equipment, where: e.hero_id == ^id) |> Repo.delete_all()
    from(j in JournalEntry, where: j.hero_id == ^id) |> Repo.delete_all()
    from(a in ActiveQuest, where: a.hero_id == ^id) |> Repo.delete_all()
    from(r in Reputation, where: r.hero_id == ^id) |> Repo.delete_all()

    Repo.delete!(hero)
    json(conn, %{message: "Hero deleted"})
  end

  def add_gold(conn, %{"id" => id} = params) do
    hero = Repo.get(Hero, id)
    if !hero, do: conn |> put_status(:not_found) |> json(%{detail: "Hero not found"}) |> halt()

    amount = params |> Map.get("amount", "0") |> to_string() |> String.to_integer()
    Repo.update!(Hero.changeset(hero, %{gold: hero.gold + amount}))
    json(conn, %{message: "Added #{amount} gold", gold: hero.gold + amount})
  end

  def add_xp(conn, %{"id" => id} = params) do
    hero = Repo.get(Hero, id)
    if !hero, do: conn |> put_status(:not_found) |> json(%{detail: "Hero not found"}) |> halt()

    amount = params |> Map.get("amount", "100") |> to_string() |> String.to_integer()
    new_xp = hero.xp + amount
    {new_level, remaining_xp, new_xp_to_next} = level_up(hero.level, new_xp, hero.xp_to_next)

    Repo.update!(Hero.changeset(hero, %{
      xp: remaining_xp, level: new_level, xp_to_next: new_xp_to_next,
      max_hp: hero.max_hp + (new_level - hero.level) * 10,
      hp: hero.max_hp + (new_level - hero.level) * 10,
    }))

    json(conn, %{message: "Added #{amount} XP", level: new_level, xp: remaining_xp})
  end

  def force_tick(conn, %{"id" => id}) do
    {:ok, result} = TesIdle.Game.Pipeline.tick(id)
    json(conn, %{message: "Tick completed", state_from: result[:state_from], state_to: result[:state_to],
                  entry_type: get_in(result, [:narrative, :type]),
                  text: (get_in(result, [:narrative, :text]) || "") |> String.slice(0, 80)})
  end

  defp level_up(level, xp, xp_to_next) when xp >= xp_to_next do
    new_level = level + 1
    remaining = xp - xp_to_next
    new_xp_to_next = trunc(xp_to_next * 1.5)
    level_up(new_level, remaining, new_xp_to_next)
  end
  defp level_up(level, xp, xp_to_next), do: {level, xp, xp_to_next}
end

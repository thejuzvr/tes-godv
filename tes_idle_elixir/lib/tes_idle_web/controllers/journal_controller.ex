defmodule TesIdleWeb.JournalController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, JournalEntry}
  import Ecto.Query

  def index(conn, params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    if !hero, do: conn |> put_status(:not_found) |> json(%{detail: "Hero not found"}) |> halt()

    limit = Map.get(params, "limit", "50") |> String.to_integer() |> min(200)
    offset = Map.get(params, "offset", "0") |> String.to_integer()
    entry_type = Map.get(params, "entry_type")

    query = from je in JournalEntry, where: je.hero_id == ^hero.id, order_by: [desc: je.created_at]
    query = if entry_type, do: from(je in query, where: je.entry_type == ^entry_type), else: query

    entries = query |> limit(^limit) |> offset(^offset) |> Repo.all()

    json(conn, Enum.map(entries, fn e ->
      %{
        id: e.id, entry_type: e.entry_type, text: e.text,
        xp_gained: e.xp_gained, gold_gained: e.gold_gained,
        item_name: e.item_name, monster_name: e.monster_name,
        location_name: e.location_name, created_at: e.created_at,
        chapter: e.chapter, chapter_title: e.chapter_title, motive: e.motive,
      }
    end))
  end

  def count(conn, _params) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    if !hero, do: conn |> put_status(:not_found) |> json(%{detail: "Hero not found"}) |> halt()

    total = Repo.one(from je in JournalEntry, where: je.hero_id == ^hero.id, select: count(je.id))
    json(conn, %{count: total})
  end
end

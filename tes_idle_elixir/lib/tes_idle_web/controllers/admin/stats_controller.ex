defmodule TesIdleWeb.Admin.StatsController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{User, Hero, JournalEntry, NarrativeTemplate}
  import Ecto.Query

  def index(conn, _params) do
    users = Repo.one(from u in User, select: count(u.id))
    heroes = Repo.one(from h in Hero, select: count(h.id))
    journal = Repo.one(from j in JournalEntry, select: count(j.id))
    templates = Repo.one(from t in NarrativeTemplate, select: count(t.id))

    json(conn, %{
      users: users,
      heroes: heroes,
      journal_entries: journal,
      narrative_templates: templates,
      monsters: 0,
      items: 0,
      active_loops: 0,
    })
  end
end

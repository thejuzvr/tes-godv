defmodule TesIdleWeb.Controllers.JournalTest do
  @moduledoc """
  Лента хроники: курсорная пагинация и «итоги отсутствия»
  (docs/JOURNAL_RETENTION_ARCHITECTURE.md, раздел 9).
  """
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  alias TesIdle.Game.Journal.{Aggregator, Milestones}
  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, JournalEntry, User}

  @endpoint TesIdleWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    suffix = System.unique_integer([:positive])

    user =
      Repo.insert!(%User{
        username: "jr_#{suffix}",
        email: "jr_#{suffix}@test.gg",
        password_hash: "x"
      })

    hero =
      Repo.insert!(%Hero{
        user_id: user.id,
        name: "Летописец #{suffix}",
        race: "Норд",
        hero_class: "Воин"
      })

    %{user: user, hero: hero}
  end

  defp conn_for(user) do
    {:ok, token, _} = TesIdle.Guardian.encode_and_sign(user)

    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("accept", "application/json")
  end

  defp entry(hero, type, minutes_ago) do
    at =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-minutes_ago * 60, :second)
      |> NaiveDateTime.truncate(:second)

    Repo.insert!(%JournalEntry{
      hero_id: hero.id,
      entry_type: type,
      text: "Запись #{type}",
      created_at: at
    })
  end

  test "returns an object with entries and pagination flags", %{user: user, hero: hero} do
    for i <- 1..5, do: entry(hero, "explore", i)

    body = conn_for(user) |> get("/api/v1/journal?limit=3") |> json_response(200)

    assert length(body["entries"]) == 3
    assert body["has_more"]
    assert is_binary(body["next_cursor"])
    assert body["limit"] == 3
  end

  test "cursor pagination returns distinct pages without duplicates", %{user: user, hero: hero} do
    for i <- 1..10, do: entry(hero, "explore", i)

    first = conn_for(user) |> get("/api/v1/journal?limit=4") |> json_response(200)
    assert length(first["entries"]) == 4

    second =
      conn_for(user)
      |> get("/api/v1/journal?limit=4&cursor=#{URI.encode_www_form(first["next_cursor"])}")
      |> json_response(200)

    assert length(second["entries"]) == 4

    first_ids = Enum.map(first["entries"], & &1["id"])
    second_ids = Enum.map(second["entries"], & &1["id"])

    # страницы не пересекаются — курсор работает, а не повторяет offset
    assert MapSet.disjoint?(MapSet.new(first_ids), MapSet.new(second_ids))
  end

  test "last page reports has_more false and no cursor", %{user: user, hero: hero} do
    for i <- 1..3, do: entry(hero, "explore", i)

    body = conn_for(user) |> get("/api/v1/journal?limit=10") |> json_response(200)

    assert length(body["entries"]) == 3
    refute body["has_more"]
    assert body["next_cursor"] == nil
  end

  test "garbage cursor is ignored instead of erroring", %{user: user, hero: hero} do
    entry(hero, "explore", 1)

    for cursor <- ["hax", "not|a|date", "2026-01-01T00:00:00|nope", ""] do
      resp =
        conn_for(user)
        |> get("/api/v1/journal?limit=5&cursor=#{URI.encode_www_form(cursor)}")

      assert resp.status == 200
    end
  end

  test "legacy offset still works for the old frontend", %{user: user, hero: hero} do
    for i <- 1..6, do: entry(hero, "explore", i)

    page2 = conn_for(user) |> get("/api/v1/journal?limit=3&offset=3") |> json_response(200)
    assert length(page2["entries"]) == 3

    page1 = conn_for(user) |> get("/api/v1/journal?limit=3") |> json_response(200)
    ids1 = Enum.map(page1["entries"], & &1["id"])
    ids2 = Enum.map(page2["entries"], & &1["id"])
    assert MapSet.disjoint?(MapSet.new(ids1), MapSet.new(ids2))
  end

  test "entry_type filter narrows the feed", %{user: user, hero: hero} do
    entry(hero, "explore", 1)
    entry(hero, "hero_victory", 2)
    entry(hero, "explore", 3)

    body = conn_for(user) |> get("/api/v1/journal?entry_type=hero_victory") |> json_response(200)

    assert length(body["entries"]) == 1
    assert hd(body["entries"])["entry_type"] == "hero_victory"
  end

  test "limit is bounded so a client cannot request everything", %{user: user, hero: hero} do
    for i <- 1..5, do: entry(hero, "explore", i)

    body = conn_for(user) |> get("/api/v1/journal?limit=99999") |> json_response(200)
    assert body["limit"] == 200
  end

  test "count reports both retained rows and lifetime totals", %{user: user, hero: hero} do
    entry(hero, "explore", 1)
    entry(hero, "explore", 2)
    # сквозные счётчики говорят, что событий было больше, чем строк осталось
    Aggregator.record_published(hero.id, "explore")
    Aggregator.record_published(hero.id, "explore")
    Aggregator.record_published(hero.id, "explore")

    body = conn_for(user) |> get("/api/v1/journal/count") |> json_response(200)

    assert body["count"] == 2
    assert body["totals"]["created"] == 3
  end

  test "summary distinguishes empty feed from actual offline progress", %{user: user, hero: hero} do
    # Хроника пуста (всё подавлено троттлингом), но события были
    Aggregator.record_suppressed(hero.id, "smell_flowers")
    Aggregator.record_suppressed(hero.id, "watch_sunset")
    Milestones.record(hero, "level_threshold", %{text: "Достиг 10 уровня", title: "Новый порог"})

    body = conn_for(user) |> get("/api/v1/journal/summary") |> json_response(200)

    # ноль строк в ленте...
    assert body["week"]["entries"] == 0
    # ...но прогресс виден: события были, веха есть
    assert body["totals"]["created"] == 2
    assert body["totals"]["suppressed"] == 2
    assert body["milestones"] == 1
  end

  test "summary counts week economics from retained entries", %{user: user, hero: hero} do
    Repo.insert!(%JournalEntry{
      hero_id: hero.id,
      entry_type: "hero_victory",
      text: "Победа",
      xp_gained: 40,
      gold_gained: 15,
      created_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    })

    body = conn_for(user) |> get("/api/v1/journal/summary") |> json_response(200)

    assert body["week"]["entries"] == 1
    assert body["week"]["xp"] == 40
    assert body["week"]["gold"] == 15
  end
end

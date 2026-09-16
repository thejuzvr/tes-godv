defmodule TesIdle.Game.Journal.ChaptersTest do
  @moduledoc "S-3-T: главы дневника — границы, заголовки, мотивы, новости мира."
  use ExUnit.Case, async: true

  alias TesIdle.Game.{GameContext, Journal.Chapters}
  alias TesIdle.Schemas.Hero

  @cfg %{
    "break_events" => ["war_declared", "dragon", "eclipse", "monster_wave"],
    "news_events" => ["war_declared", "dragon", "eclipse", "monster_wave", "fair"],
    "news_chance" => 1.0,
    "titles" => %{
      "day" => "Тихий день",
      "war_declared" => "Война за холмами",
      "dragon" => "Дракон в небе",
      "eclipse" => "Дни без солнца",
      "monster_wave" => "Нечисть выходит из пустошей",
      "arrest" => "Цена чужого добра",
      "level_up" => "Новая ступень",
    },
  }

  defp hero(day) do
    %Hero{name: "Глава", game_day: day, location_id: nil}
  end

  defp ctx(world, journal_cfg \\ @cfg) do
    %GameContext{configs: %{"journal" => journal_cfg}, world: world}
  end

  defp world(events) do
    %{"events" => events, "wars" => [], "density" => %{}, "prices" => %{}}
  end

  defp ev(type, id, loc_id \\ nil) do
    %{"id" => id, "type" => type, "name" => "Имя события", "location_id" => loc_id, "ttl" => 5}
  end

  # --- Границы глав ---

  test "новый игровой день открывает главу с заголовком «День N. Тихий день»" do
    state = %{"journal" => %{"chapter" => 2, "chapter_day" => 3, "title" => "День 3. Тихий день"}}

    {chapter, title, j} = Chapters.ensure(hero(4), state, ctx(world([])))

    assert chapter == 3
    assert title == "День 4. Тихий день"
    assert j["chapter"] == 3
    assert j["chapter_day"] == 4
  end

  test "тот же день — глава не меняется" do
    state = %{"journal" => %{"chapter" => 2, "chapter_day" => 4, "title" => "День 4. Тихий день"}}

    {chapter, title, _j} = Chapters.ensure(hero(4), state, ctx(world([])))

    assert chapter == 2
    assert title == "День 4. Тихий день"
  end

  test "перелом: дракон открывает главу посреди дня с заголовком «Дракон в небе»" do
    state = %{"journal" => %{"chapter" => 1, "chapter_day" => 5, "title" => "День 5. Тихий день"}}
    w = world([ev("dragon", "d-1")])

    {chapter, title, _j} = Chapters.ensure(hero(5), state, ctx(w), ["world"])

    assert chapter == 2
    assert title == "День 5. Дракон в небе"
  end

  test "повторное то же событие не открывает главу (break_seen)" do
    state = %{
      "journal" => %{
        "chapter" => 2, "chapter_day" => 5, "title" => "День 5. Дракон в небе",
        "break_seen" => ["d-1"],
      },
    }
    w = world([ev("dragon", "d-1")])

    {chapter, _title, _j} = Chapters.ensure(hero(5), state, ctx(w), ["world"])

    assert chapter == 2
  end

  test "новая волна монстров при виденном драконе — новая глава «Нечисть…»" do
    state = %{
      "journal" => %{
        "chapter" => 2, "chapter_day" => 5, "title" => "День 5. Дракон в небе",
        "break_seen" => ["d-1"],
      },
    }
    w = world([ev("dragon", "d-1"), ev("monster_wave", "mw-2")])

    {chapter, title, _j} = Chapters.ensure(hero(5), state, ctx(w), ["world"])

    assert chapter == 3
    assert title == "День 5. Нечисть выходит из пустошей"
  end

  test "событие в чужой локации не открывает главу" do
    state = %{"journal" => %{"chapter" => 1, "chapter_day" => 5, "title" => "День 5. Тихий день"}}
    w = world([ev("dragon", "d-9", "other-loc-uuid")])

    {chapter, _title, _j} = Chapters.ensure(hero(5), state, ctx(w), ["world"])

    assert chapter == 1
  end

  test "арест и уровень — свои главы" do
    state = %{"journal" => %{"chapter" => 1, "chapter_day" => 5, "title" => "День 5. Тихий день"}}

    {chapter, title, j} = Chapters.ensure(hero(5), state, ctx(world([])), ["arrest"])
    assert chapter == 2 and title == "День 5. Цена чужого добра"
    assert j["jail_chapter"] == 2

    {chapter2, title2, _} = Chapters.ensure(hero(5), %{"journal" => j}, ctx(world([])), ["level_up"])
    assert chapter2 == 3 and title2 == "День 5. Новая ступень"
  end

  # --- Мотивы решений ---

  test "мотив строится из последней записи decision_log" do
    brain = %{
      "decision_log" => [
        %{"goal" => "heal", "utility" => 0.62, "reasons" => ["дракон в небе: осторожный пережидает (-0.12)"]},
      ],
    }

    motive = Chapters.motive_for(brain)

    assert String.starts_with?(motive, "heal (0.62)")
    assert String.contains?(motive, "дракон в небе")
  end

  test "мотив nil при пустом логе" do
    assert Chapters.motive_for(%{}) == nil
    assert Chapters.motive_for(nil) == nil
  end

  # --- Новости мира ---

  test "новость: глобальное событие приходит с шансом (news_chance = 1.0) и попадает в news_seen" do
    state = %{"journal" => %{"chapter" => 1, "chapter_day" => 5, "title" => "День 5. Тихий день"}}
    w = world([ev("eclipse", "e-1")])

    assert {event, j} = Chapters.world_news_candidate(hero(5), state, ctx(w))

    assert event["type"] == "eclipse"
    assert j["news_seen"] == ["e-1"]
  end

  test "новость в чужой локации не приходит" do
    state = %{"journal" => %{"chapter" => 1, "chapter_day" => 5, "title" => "День 5. Тихий день"}}
    w = world([ev("fair", "f-1", "not-my-loc")])

    assert Chapters.world_news_candidate(hero(5), state, ctx(w)) == nil
  end

  test "виденная новость не повторяется" do
    state = %{
      "journal" => %{"chapter" => 1, "chapter_day" => 5, "title" => "День 5. Тихий день", "news_seen" => ["e-1"]},
    }
    w = world([ev("eclipse", "e-1")])

    assert Chapters.world_news_candidate(hero(5), state, ctx(w)) == nil
  end

  test "fair в локации героя — новость приходит" do
    h = %{hero(5) | location_id: "my-loc"}
    state = %{"journal" => %{"chapter" => 1, "chapter_day" => 5, "title" => "День 5. Тихий день"}}
    w = world([ev("fair", "f-2", "my-loc")])

    assert {event, _j} = Chapters.world_news_candidate(h, state, ctx(w))
    assert event["type"] == "fair"
  end
end

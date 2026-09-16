defmodule TesIdle.World.ConstructionTest do
  use ExUnit.Case, async: true

  alias TesIdle.World.Construction

  # Учебный конфиг: 2 проекта, пороги 300 и 500, трюккл 0 (в тестах шагаем руками)
  @cfg %{
    "min_donation" => 10,
    "world_trickle" => 0,
    "top_donors_size" => 3,
    "projects" => [
      %{"name" => "Часовня", "target" => 300, "stages" => ["фундамент", "стены", "крыша"]},
      %{"name" => "Мост", "target" => 500, "stages" => ["опоры", "настил"]}
    ]
  }

  defp block, do: Construction.init_block()

  # donate/step принимают ВЕСЬ словарь конфигов (game_configs), а не только construction
  defp cfg, do: %{"construction" => @cfg}

  test "init_block: старт с первого проекта, нули" do
    b = block()
    assert b["project"] == 0
    assert b["collected"] == 0
    assert b["stage"] == 0
    assert b["top_donors"] == []
    assert b["history"] == []
  end

  test "donate: копит фонд и трекает донатера суммой" do
    {b, events} = Construction.donate(block(), "Йоррг", 50, cfg(), 0)
    assert b["collected"] == 50
    assert events == []

    {b, _} = Construction.donate(b, "Йоррг", 20, cfg(), 0)
    assert [%{"name" => "Йоррг", "gold" => 70}] = b["top_donors"]
  end

  test "donate: ноль и отрицательное игнорируются" do
    {b, _} = Construction.donate(block(), "X", 0, cfg(), 0)
    assert b["collected"] == 0
    {b, _} = Construction.donate(b, "X", -5, cfg(), 0)
    assert b["collected"] == 0
  end

  test "стадии сдвигаются на равных долях цели (300/3 = 100 за стадию)" do
    {b, events} = Construction.donate(block(), "Йоррг", 100, cfg(), 5)
    assert b["stage"] == 1
    assert [%{"type" => "construction", "name" => name}] = events
    assert name =~ "фундамент"

    # крупный донат доводит до последней стадии, но не до цели (100+190=290 < 300)
    {b, events} = Construction.donate(b, "Сингрид", 190, cfg(), 6)
    assert b["stage"] == 2
    assert length(events) == 1
    assert [%{"name" => name2}] = events
    assert name2 =~ "стены"

    # а вот кит-донат может закрыть проект целиком за один взнос
    {b, events} = Construction.donate(b, "Кит", 500, cfg(), 7)
    assert b["project"] == 1
    assert b["collected"] == 0
    assert b["stage"] == 0
    completion = Enum.find(events, &(&1["desc"] =~ "готово"))
    assert completion != nil
  end

  test "завершение проекта: история пишется, конвейер переходит к следующему, счётчики обнуляются" do
    {b, _} = Construction.donate(block(), "Йоррг", 300, cfg(), 7)
    assert b["project"] == 1
    assert b["collected"] == 0
    assert b["stage"] == 0
    assert [%{"name" => "Часовня"}] = b["history"]

    # после завершения — копим уже Мост (порог стадии 500/2 = 250)
    {b, events} = Construction.donate(b, "Йоррг", 250, cfg(), 8)
    assert b["stage"] == 1
    assert events != []
  end

  test "конвейер зациклен: после последнего проекта — снова первый" do
    b = %{block() | "project" => 1}
    {b, _} = Construction.donate(b, "Кагрен", 500, cfg(), 9)
    assert b["project"] == 0
    assert b["history"] |> List.first() |> Map.get("name") == "Мост"
  end

  test "top_donors: капается до top_donors_size, сортировка по золоту" do
    b = block()

    {b, _} = Construction.donate(b, "А", 10, cfg(), 0)
    {b, _} = Construction.donate(b, "Б", 30, cfg(), 0)
    {b, _} = Construction.donate(b, "В", 20, cfg(), 0)
    {b, _} = Construction.donate(b, "Г", 5, cfg(), 0)

    names = Enum.map(b["top_donors"], & &1["name"])
    assert names == ["Б", "В", "А"] # cap 3, "Г" вытеснен
  end

  test "step: паломники добавляют trickle, но не попадают в топ-донатеров" do
    trickle_cfg = %{"construction" => Map.put(@cfg, "world_trickle", 25)}
    {b, _} = Construction.step(block(), trickle_cfg, 1)
    assert b["collected"] == 25
    assert b["top_donors"] == []
  end

  test "summary: честный прогресс и имена стадий" do
    {b, _} = Construction.donate(block(), "Йоррг", 150, cfg(), 0)
    s = Construction.summary(b, cfg())
    assert s["project"] == "Часовня"
    assert s["stage"] == "стены"
    assert s["stage_index"] == 1
    assert s["stages_total"] == 3
    assert s["progress"] == 0.5
    assert [%{"name" => "Йоррг", "gold" => 150}] = s["top_donors"]
  end

  test "конфиг из game_configs перекрывает дефолты, недостающие ключи — из дефолтов" do
    merged = Construction.config(%{"construction" => %{"world_trickle" => 5}})
    assert merged["world_trickle"] == 5
    assert merged["min_donation"] == 10
    assert length(merged["projects"]) == 3
  end
end

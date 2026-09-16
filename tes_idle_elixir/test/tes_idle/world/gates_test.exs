defmodule TesIdle.World.GatesTest do
  use ExUnit.Case, async: true

  alias TesIdle.World.Gates

  @cfg %{"open_chance" => 0.5, "fund_target" => 300, "deadline_ticks" => 72, "cooldown_ticks" => 48}

  @locations [
    {"11111111-1111-1111-1111-111111111111", "Вайтран", "Вайтран", "city"},
    {"22222222-2222-2222-2222-222222222222", "Ривервуд", "Фолкрит", "village"},
    {"33333333-3333-3333-3333-333333333333", "Пустоши", "Истмарк", "wilderness"}
  ]

  defp cfg, do: @cfg

  test "init_block: врата закрыты, cooldown нулевой" do
    b = Gates.init_block()
    assert b["status"] == "closed"
    assert b["fund"] == 0
    assert b["cooldown_until_tick"] == 0
  end

  test "step: cooldown блокирует открытие" do
    b = Gates.init_block() |> Map.put("cooldown_until_tick", 100)
    {b2, events} = Gates.step(b, cfg(), 50, @locations, 0.0)
    assert b2["status"] == "closed"
    assert events == []
  end

  test "step: roll ниже open_chance — врата открываются над ГОРОДОМ с событием" do
    {b, events} = Gates.step(Gates.init_block(), cfg(), 10, @locations, 0.1)
    assert b["status"] == "open"
    assert b["location_id"] in ["11111111-1111-1111-1111-111111111111"]
    assert b["fund"] == 0
    assert b["target"] == 300
    assert b["deadline_tick"] == 10 + 72
    assert [%{"type" => "oblivion_gate", "location_id" => loc_id, "desc" => desc}] = events
    assert loc_id == b["location_id"]
    assert desc =~ "багровый"
  end

  test "step: roll выше open_chance — тишина" do
    {b, events} = Gates.step(Gates.init_block(), cfg(), 10, @locations, 0.9)
    assert b["status"] == "closed"
    assert events == []
  end

  test "step: открытые врата до срока — без изменений" do
    {b, _} = Gates.step(Gates.init_block(), cfg(), 10, @locations, 0.1)
    {b2, events} = Gates.step(b, cfg(), 50, @locations, 0.9)
    assert b2["status"] == "open"
    assert events == []
  end

  test "step: срок вышел, фонд не собран — врата схлопываются + gate_fallen + cooldown" do
    {b, _} = Gates.step(Gates.init_block(), cfg(), 10, @locations, 0.1)

    {b2, events} = Gates.step(b, cfg(), 10 + 72, @locations, 0.5)
    assert b2["status"] == "closed"
    assert b2["cooldown_until_tick"] == 10 + 72 + 48
    assert [%{"type" => "gate_fallen"}] = events
  end

  test "donate: копит фонд и трекает донатера; закрытие при полной казне + gate_closed" do
    {b, _} = Gates.step(Gates.init_block(), cfg(), 10, @locations, 0.1)

    {:ok, b, [], false} = Gates.donate(b, "hero-1", "Йоррг", 100, cfg(), 20)
    assert b["fund"] == 100
    assert b["donors"]["hero-1"] == 100
    assert b["donor_names"]["hero-1"] == "Йоррг"

    {:ok, b, events, true} = Gates.donate(b, "hero-1", "Йоррг", 200, cfg(), 21)
    assert b["fund"] == 300
    assert b["status"] == "closed"
    assert b["cooldown_until_tick"] == 21 + 48
    assert [%{"type" => "gate_closed", "desc" => desc}] = events
    assert desc =~ "300"
  end

  test "donate: не открыт — :not_open; плохая сумма — :bad_amount" do
    assert {:error, :not_open} = Gates.donate(Gates.init_block(), "h", "X", 100, cfg(), 0)

    {b, _} = Gates.step(Gates.init_block(), cfg(), 10, @locations, 0.1)
    assert {:error, :bad_amount} = Gates.donate(b, "h", "X", 0, cfg(), 11)
    assert {:error, :bad_amount} = Gates.donate(b, "h", "X", -5, cfg(), 11)
  end

  test "summary: наружу статус/прогресс/срок/топ без сырых тиков" do
    {b, _} = Gates.step(Gates.init_block(), cfg(), 10, @locations, 0.1)
    {:ok, b, _, _} = Gates.donate(b, "hero-1", "Йоррг", 100, cfg(), 20)

    s = Gates.summary(b, 30)
    assert s["status"] == "open"
    assert s["fund"] == 100
    assert s["target"] == 300
    assert s["ticks_left"] == 72 - 20
    assert [%{name: "Йоррг", amount: 100}] = s["top_donors"]

    closed = Gates.summary(%{b | "status" => "closed"}, 999)
    assert closed["ticks_left"] == nil
  end

  test "cfg: дефолты при пустом конфиге, merge с БД-блоком" do
    assert Gates.cfg(%{})["fund_target"] == 2000
    assert Gates.cfg(%{"gates" => %{"fund_target" => 500}})["fund_target"] == 500
    assert Gates.cfg(%{"gates" => %{"fund_target" => 500}})["open_chance"] == 0.02
  end

  test "Economy: открытые врата над городом — цены ×1.3 (регион в опасности)" do
    alias TesIdle.World.Economy

    city = "11111111-1111-1111-1111-111111111111"
    other = "44444444-4444-4444-4444-444444444444"
    prices = %{city => %{"potion" => 1.0}, other => %{"potion" => 1.0}}
    events = [%{"type" => "oblivion_gate", "location_id" => city, "ttl" => 10}]

    stepped = Economy.step(prices, [], events)
    assert_in_delta stepped[city]["potion"], 1.3, 0.01
    assert_in_delta stepped[other]["potion"], 1.0, 0.01
  end
end

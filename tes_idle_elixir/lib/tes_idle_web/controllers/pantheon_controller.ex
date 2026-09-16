defmodule TesIdleWeb.PantheonController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.Hero
  import Ecto.Query

  def kills(conn, params) do
    limit = Map.get(params, "limit", "50") |> String.to_integer() |> min(100)
    heroes = Repo.all(
      from h in Hero,
        order_by: [desc: h.total_kills, desc: h.level],
        limit: ^limit,
        select: %{hero_name: h.name, hero_level: h.level, value: h.total_kills}
    )
    json(conn, Enum.with_index(heroes, 1) |> Enum.map(fn {h, rank} -> Map.put(h, :rank, rank) end))
  end

  def gold(conn, params) do
    limit = Map.get(params, "limit", "50") |> String.to_integer() |> min(100)
    heroes = Repo.all(
      from h in Hero,
        where: h.total_gold_earned > 0 or h.gold > 0,
        order_by: [desc: fragment("GREATEST(?, ?)", h.total_gold_earned, h.gold)],
        limit: ^limit,
        select: %{hero_name: h.name, hero_level: h.level, value: fragment("GREATEST(?, ?)", h.total_gold_earned, h.gold)}
    )
    json(conn, Enum.with_index(heroes, 1) |> Enum.map(fn {h, rank} -> Map.put(h, :rank, rank) end))
  end

  def time(conn, params) do
    limit = Map.get(params, "limit", "50") |> String.to_integer() |> min(100)
    heroes = Repo.all(
      from h in Hero,
        where: h.total_play_time_seconds > 0,
        order_by: [desc: h.total_play_time_seconds],
        limit: ^limit,
        select: %{hero_name: h.name, hero_level: h.level, value: h.total_play_time_seconds}
    )
    json(conn, Enum.with_index(heroes, 1) |> Enum.map(fn {h, rank} -> Map.put(h, :rank, rank) end))
  end
end

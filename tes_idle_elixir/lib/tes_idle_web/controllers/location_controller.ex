defmodule TesIdleWeb.LocationController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Hero, Location}
  import Ecto.Query

  def index(conn, _params) do
    locations = Repo.all(from l in Location, order_by: l.name)
    json(conn, Enum.map(locations, fn l ->
      %{
        id: l.id, name: l.name, description: l.description,
        region: l.region, location_type: l.location_type,
        danger_level: l.danger_level, min_level: l.min_level, max_level: l.max_level,
        has_shop: l.has_shop, has_inn: l.has_inn, weather: l.weather,
        # M-2 «Карта мира»: координаты узла + флаги активностей
        map_x: l.map_x, map_y: l.map_y, flags: l.flags || %{},
      }
    end))
  end

  def travel(conn, %{"id" => location_id}) do
    user = conn.assigns.current_user
    hero = Repo.one(from h in Hero, where: h.user_id == ^user.id)
    dest = Repo.get(Location, location_id)

    cond do
      is_nil(hero) ->
        conn |> put_status(:not_found) |> json(%{detail: "Hero not found"})

      is_nil(dest) ->
        conn |> put_status(:not_found) |> json(%{detail: "Location not found"})

      # Мульти-тик занят (бой/тюрьма/рыбалка/путешествие) — ручная поездка невозможна
      true ->
        state = decode_state(hero.state_data)
        busy? = Enum.any?(["combat", "jail", "fishing", "travel", "gathering"], &Map.get(state, &1) not in [nil, false])

        if busy? do
          conn |> put_status(:conflict) |> json(%{detail: "Hero is busy"})
        else
          # Start travel
          travel_ticks = Enum.random(2..5)
          # Пишем через свежее чтение (правило единственного писателя state_data):
          # не затираем план/мозг/закон, накопленные Pipeline с момента запроса.
          fresh = Repo.reload!(hero)
          fresh_state = decode_state(fresh.state_data)
          fresh_state = Map.put(fresh_state, "travel", %{
            "destination_id" => to_string(dest.id),
            "destination_name" => dest.name,
            "ticks_left" => travel_ticks,
            "total_ticks" => travel_ticks,
          })

          fresh
          |> Hero.changeset(%{
            state: "traveling",
            state_data: Jason.encode!(fresh_state),
            fatigue: min(100, fresh.fatigue + 10),
            gold: max(0, fresh.gold - 5),
            sp: max(0, fresh.sp - 5),
          })
          |> Repo.update!()

          json(conn, %{message: "Traveling to #{dest.name}", travel_ticks: travel_ticks})
        end
    end
  end

  defp decode_state(nil), do: %{}
  defp decode_state(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, data} when is_map(data) -> data
      _ -> %{}
    end
  end
  defp decode_state(_), do: %{}
end

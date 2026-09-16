defmodule TesIdleWeb.Admin.ExportController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Location, Monster, Item, NarrativeTemplate, GameConfig}

  defp to_map(%{__struct__: struct} = s), do: s |> Map.from_struct() |> Map.drop([:__meta__] ++ struct.__schema__(:associations))
  defp to_map(v), do: v

  defp to_maps(list), do: Enum.map(list, &to_map/1)

  def export(conn, _params) do
    json(conn, %{
      locations: to_maps(Repo.all(Location)),
      monsters: to_maps(Repo.all(Monster)),
      items: to_maps(Repo.all(Item)),
      narrative_templates: to_maps(Repo.all(NarrativeTemplate)),
      game_configs: to_maps(Repo.all(GameConfig)),
    })
  end

  def export_file(conn, _params) do
    data = %{
      locations: to_maps(Repo.all(Location)),
      monsters: to_maps(Repo.all(Monster)),
      items: to_maps(Repo.all(Item)),
      narrative_templates: to_maps(Repo.all(NarrativeTemplate)),
      game_configs: to_maps(Repo.all(GameConfig)),
    }

    filename = "export_#{DateTime.utc_now() |> DateTime.to_string() |> String.replace(~r/[^0-9a-zA-Z]/, "_")}.json"
    File.mkdir_p!("priv/exports")
    File.write!("priv/exports/#{filename}", Jason.encode!(data))

    conn
    |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
    |> json(data)
  end
end

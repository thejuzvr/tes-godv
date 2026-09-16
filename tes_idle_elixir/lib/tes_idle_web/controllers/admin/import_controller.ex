defmodule TesIdleWeb.Admin.ImportController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.{Location, Monster, Item, NarrativeTemplate, GameConfig}

  def import(conn, params) do
    imported =
      0
      |> import_items(params, "locations", &Location.changeset/2, %Location{})
      |> import_items(params, "monsters", &Monster.changeset/2, %Monster{})
      |> import_items(params, "items", &Item.changeset/2, %Item{})
      |> import_narratives(params)
      |> import_items(params, "game_configs", &GameConfig.changeset/2, %GameConfig{})

    json(conn, %{imported: imported, message: "Import completed"})
  end

  # Community narrative templates go to moderation (is_active: false)
  defp import_narratives(count, params) do
    case params["narrative_templates"] do
      nil -> count
      items when is_list(items) ->
        inserted = Enum.reduce(items, 0, fn item, acc ->
          try do
            item = Map.put(item, "is_active", false)
            changeset = NarrativeTemplate.changeset(%NarrativeTemplate{}, item)
            case Repo.insert(changeset) do
              {:ok, _} -> acc + 1
              {:error, _} -> acc
            end
          rescue
            _ -> acc
          end
        end)
        count + inserted
      _ -> count
    end
  end

  defp import_items(count, params, key, changeset_fn, default_struct) do
    case params[key] do
      nil ->
        count
      items when is_list(items) ->
        inserted = Enum.reduce(items, 0, fn item, acc ->
          try do
            case changeset_fn.(default_struct, item) |> Repo.insert() do
              {:ok, _} -> acc + 1
              {:error, _} -> acc
            end
          rescue
            _ -> acc
          end
        end)
        count + inserted
      _ ->
        count
    end
  end
end

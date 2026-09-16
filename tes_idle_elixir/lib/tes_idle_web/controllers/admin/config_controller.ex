defmodule TesIdleWeb.Admin.ConfigController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.GameConfig
  import Ecto.Query

  def index(conn, _params) do
    configs = Repo.all(from c in GameConfig, order_by: c.key)
    json(conn, %{
      configs: Enum.map(configs, fn c ->
        %{key: c.key, value: Jason.decode!(c.value), description: c.description}
      end)
    })
  end

  def update(conn, %{"key" => key} = params) do
    value = Jason.encode!(params["value"] || %{})
    description = Map.get(params, "description", "")

    config = Repo.one(from c in GameConfig, where: c.key == ^key)
    if config do
      Repo.update!(GameConfig.changeset(config, %{value: value, description: description}))
    else
      Repo.insert!(%GameConfig{key: key, value: value, description: description})
    end

    json(conn, %{message: "Config updated", key: key})
  end
end

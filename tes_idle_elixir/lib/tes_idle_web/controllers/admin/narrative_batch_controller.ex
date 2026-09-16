defmodule TesIdleWeb.Admin.NarrativeBatchController do
  use TesIdleWeb, :controller

  alias TesIdle.Game.Narrative.BatchImporter

  # Dry-run only: no template or fragment selection, LLM request, or write occurs.
  def validate(conn, params) do
    json(conn, BatchImporter.validate(params))
  end

  # All-or-nothing: any invalid row (or concurrent duplicate) leaves the batch untouched.
  def import(conn, params) do
    case BatchImporter.import(params) do
      {:ok, response} -> conn |> put_status(:created) |> json(response)
      {:error, response} -> conn |> put_status(:unprocessable_entity) |> json(response)
    end
  end
end

defmodule TesIdleWeb.Admin.NarrativesImportController do
  use TesIdleWeb, :controller

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeTemplate
  import Ecto.Query

  def import(conn, templates) when is_list(templates) do
    imported = 0
    rejected = []

    Enum.each(templates, fn tmpl ->
      text = tmpl["text_template"] || ""
      template_type = tmpl["template_type"] || "explore"
      source = tmpl["source"] || "community"

      if String.trim(text) == "" do
        rejected ++ [%{text: "(empty)", errors: ["Empty text"]}]
      else
        existing = Repo.one(from t in NarrativeTemplate, where: t.text_template == ^text)
        if existing do
          rejected ++ [%{text: String.slice(text, 0, 80), errors: ["Already exists"]}]
        else
          Repo.insert!(%NarrativeTemplate{
            template_type: template_type,
            text_template: text,
            source: source,
            is_active: source == "system",
          })
        end
      end
    end)

    json(conn, %{imported: imported, rejected: length(rejected), errors: rejected})
  end
end

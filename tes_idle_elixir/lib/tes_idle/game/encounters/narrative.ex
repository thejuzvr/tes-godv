defmodule TesIdle.Game.Encounters.Narrative do
  @moduledoc """
  Strict encounter-only narrative selection and rendering.

  The renderer accepts a fixed allowlist. It deliberately does not call the
  generic action narrative engine and cannot inspect a Hero struct.
  """

  import Ecto.Query

  alias TesIdle.Repo
  alias TesIdle.Schemas.NarrativeTemplate

  @types %{
    "initiator" => "hero_encounter_initiator",
    "counterpart" => "hero_encounter_counterpart"
  }
  @allowed_vars ~w(hero_name other_hero_name location_name encounter_kind)

  @type safe_context :: %{
          required(:hero_name) => String.t(),
          required(:other_hero_name) => String.t(),
          required(:location_name) => String.t(),
          required(:encounter_kind) => String.t()
        }

  @spec build(String.t(), safe_context(), String.t()) ::
          nil | %{template_id: Ecto.UUID.t(), text: String.t()}
  def build(role, context, selection_key) when is_map(context) do
    with template_type when is_binary(template_type) <- Map.get(@types, role),
         templates when templates != [] <- load(template_type),
         template <- select_template(templates, selection_key),
         {:ok, text} <- render(template.text_template, context) do
      %{template_id: template.id, text: text}
    else
      _ -> nil
    end
  end

  @doc "Deterministically selects a template from an already ordered list."
  def select_template([], _key), do: nil

  def select_template(templates, key) do
    Enum.at(templates, :erlang.phash2(key, length(templates)))
  end

  @doc "Renders only the dedicated encounter variable allowlist."
  @spec render(String.t(), map()) :: {:ok, String.t()} | {:error, atom()}
  def render(template, context) when is_binary(template) and is_map(context) do
    placeholders =
      Regex.scan(~r/\{([^{}]+)\}/, template, capture: :all_but_first)
      |> List.flatten()

    if Enum.all?(
         placeholders,
         &(&1 in @allowed_vars and is_binary(Map.get(context, String.to_atom(&1))))
       ) do
      text =
        Enum.reduce(@allowed_vars, template, fn var, acc ->
          value = Map.get(context, String.to_atom(var))
          if is_binary(value), do: String.replace(acc, "{#{var}}", value), else: acc
        end)

      {:ok, text}
    else
      {:error, :unsafe_or_missing_variable}
    end
  end

  defp load(template_type) do
    Repo.all(
      from template in NarrativeTemplate,
        where:
          template.template_type == ^template_type and template.is_active == true and
            template.source == "system",
        order_by: [asc: template.id]
    )
  end
end

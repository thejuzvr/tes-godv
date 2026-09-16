defmodule TesIdle.Game.Encounters.PublicParticipant do
  @moduledoc """
  Privacy boundary for encounter narratives.

  Only an encounter-safe label and public identifier leave this module. Hero
  structs and their private fields must never be passed to narrative rendering.
  """

  @type t :: %{id: Ecto.UUID.t(), label: String.t()}

  @spec from_hero(struct(), struct() | nil, String.t()) :: t()
  def from_hero(hero, settings, fallback_label) do
    %{id: hero.id, label: label(hero, settings, fallback_label)}
  end

  # Missing settings use the schema/API privacy default: reveal during an encounter.
  defp label(hero, nil, _fallback), do: hero.name

  defp label(hero, %{reveal_name: reveal}, _fallback)
       when reveal in ["encounter", "public"],
       do: hero.name

  # "guild" requires a proven shared-guild context; Resolver deliberately does not
  # infer one, so it falls back rather than leaking the name.
  defp label(_hero, _settings, fallback), do: fallback
end

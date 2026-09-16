defmodule TesIdle.Schemas.NarrativeTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "narrative_templates" do
    field :template_type, :string
    field :text_template, :string
    field :conditions, :string
    field :variables, :string
    field :mood_min, :float
    field :mood_max, :float
    field :location_id, :binary_id
    field :is_active, :boolean, default: true
    field :source, :string, default: "system"

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(narrative_template, attrs) do
    narrative_template
    |> cast(attrs, [
      :template_type, :text_template, :conditions, :variables,
      :mood_min, :mood_max, :location_id, :is_active, :source,
    ])
    |> validate_required([:template_type, :text_template])
  end
end

defmodule TesIdle.Schemas.NarrativeFragment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "narrative_fragments" do
    field :pool_key, :string
    field :text, :string
    field :weight, :integer, default: 1
    field :source, :string, default: "system"
    field :is_active, :boolean, default: true

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(fragment, attrs) do
    fragment
    |> cast(attrs, [:pool_key, :text, :weight, :source, :is_active])
    |> validate_required([:pool_key, :text])
  end
end

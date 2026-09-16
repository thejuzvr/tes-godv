defmodule TesIdle.Schemas.JournalEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "journal_entries" do
    field :entry_type, :string
    field :text, :string
    field :xp_gained, :integer, default: 0
    field :gold_gained, :integer, default: 0
    field :item_name, :string
    field :monster_name, :string
    field :location_name, :string
    field :chapter, :integer
    field :chapter_title, :string
    field :motive, :string

    belongs_to :hero, TesIdle.Schemas.Hero, type: :binary_id

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(journal_entry, attrs) do
    journal_entry
    |> cast(attrs, [:entry_type, :text, :xp_gained, :gold_gained, :item_name, :monster_name, :location_name, :chapter, :chapter_title, :motive, :hero_id])
    |> validate_required([:entry_type, :text, :hero_id])
  end
end

defmodule TesIdle.Schemas.Sharpening do
  @moduledoc """
  C-2 «Небесная кузня»: уровень заточки предмета экипировки героя.
  Ключ (hero_id, item_id) — заточка личная, каталоговые item общие.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sharpenings" do
    field :level, :integer, default: 0

    belongs_to :hero, TesIdle.Schemas.Hero
    belongs_to :item, TesIdle.Schemas.Item

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(sharpening, attrs) do
    sharpening
    |> Ecto.Changeset.cast(attrs, [:hero_id, :item_id, :level])
    |> Ecto.Changeset.validate_required([:hero_id, :item_id, :level])
    |> Ecto.Changeset.unique_constraint([:hero_id, :item_id])
  end
end

defmodule TesIdle.Schemas.HeroBlock do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "hero_blocks" do
    belongs_to :blocker, TesIdle.Schemas.Hero
    belongs_to :blocked, TesIdle.Schemas.Hero

    timestamps(inserted_at: :created_at, updated_at: false)
  end

  def changeset(block, attrs) do
    block
    |> cast(attrs, [:blocker_id, :blocked_id])
    |> validate_required([:blocker_id, :blocked_id])
    |> validate_distinct_heroes()
    |> unique_constraint([:blocker_id, :blocked_id], name: :hero_blocks_blocker_blocked_uidx)
    |> foreign_key_constraint(:blocker_id)
    |> foreign_key_constraint(:blocked_id)
  end

  defp validate_distinct_heroes(changeset) do
    blocker_id = get_field(changeset, :blocker_id)
    blocked_id = get_field(changeset, :blocked_id)

    if is_binary(blocker_id) and blocker_id == blocked_id do
      add_error(changeset, :blocked_id, "must be a different hero")
    else
      changeset
    end
  end
end

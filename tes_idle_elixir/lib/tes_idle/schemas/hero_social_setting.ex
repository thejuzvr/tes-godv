defmodule TesIdle.Schemas.HeroSocialSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "hero_social_settings" do
    field :encounter_mode, :string, default: "live_only"
    field :reveal_name, :string, default: "encounter"
    field :daily_cap, :integer
    field :cooldown_seconds, :integer

    belongs_to :hero, TesIdle.Schemas.Hero

    timestamps(inserted_at: :created_at)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:hero_id, :encounter_mode, :reveal_name, :daily_cap, :cooldown_seconds])
    |> validate_required([:hero_id, :encounter_mode, :reveal_name])
    |> validate_number(:daily_cap, greater_than_or_equal_to: 0)
    |> validate_number(:cooldown_seconds, greater_than_or_equal_to: 0)
    |> unique_constraint(:hero_id, name: :hero_social_settings_hero_uidx)
    |> foreign_key_constraint(:hero_id)
  end
end

defmodule TesIdle.Schemas.Location do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "locations" do
    field :name, :string
    field :description, :string, default: ""
    field :region, :string, default: "Скайрим"
    field :location_type, :string, default: "village"
    field :danger_level, :string, default: "Низкая"
    field :min_level, :integer, default: 1
    field :max_level, :integer, default: 10
    field :has_shop, :boolean, default: false
    field :has_inn, :boolean, default: false
    field :weather, :string, default: "Ясно"
    # Флаги активностей: %{"water" => true, "gather_nodes" => [...], "guard_level" => 2}
    field :flags, :map, default: %{}
    # M-2 «Карта мира»: координаты узла на SVG-карте (viewBox 1000×700)
    field :map_x, :integer
    field :map_y, :integer

    has_many :heroes, TesIdle.Schemas.Hero
    has_many :monsters, TesIdle.Schemas.Monster

    # timestamps()
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [
      :name, :description, :region, :location_type, :danger_level,
      :min_level, :max_level, :has_shop, :has_inn, :weather, :flags,
      :map_x, :map_y,
    ])
    |> validate_required([:name, :region, :location_type])
    |> unique_constraint(:name)
  end
end

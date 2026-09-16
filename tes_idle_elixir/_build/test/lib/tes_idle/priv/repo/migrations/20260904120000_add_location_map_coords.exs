defmodule TesIdle.Repo.Migrations.AddLocationMapCoords do
  @moduledoc "M-2 «Карта мира»: координаты локаций (map_x/map_y) для интерактивной SVG-карты."
  use Ecto.Migration

  def up do
    execute("ALTER TABLE locations ADD COLUMN IF NOT EXISTS map_x INTEGER;")
    execute("ALTER TABLE locations ADD COLUMN IF NOT EXISTS map_y INTEGER;")
  end

  def down do
    execute("ALTER TABLE locations DROP COLUMN IF EXISTS map_x;")
    execute("ALTER TABLE locations DROP COLUMN IF EXISTS map_y;")
  end
end

alias TesIdle.Repo
alias TesIdle.Schemas.Location

# Seed locations (map_x/map_y — координаты узла на SVG-карте мира, viewBox 1000×700.
# P-1: координаты синхронизированы с артворком Skyrim.svg (проекция провинции:
# границы холдов X 1782..29098, Y 8911..29185 → 943×700 на канвасе, поля 28.5;
# города — центры групп City_S_* артворка). Солитьюд СЗ, Виндхельм СВ, Вайтран центр, Рифтен ЮВ)
locations = [
  %{name: "Ривервуд", description: "Тихая деревня у реки Белая.", region: "Скайрим", location_type: "village", danger_level: "Низкая", min_level: 1, max_level: 5, has_shop: true, has_inn: true, map_x: 600, map_y: 300},
  %{name: "Вайтран", description: "Столица Скайрима, город на ветру.", region: "Скайрим", location_type: "city", danger_level: "Средняя", min_level: 3, max_level: 12, has_shop: true, has_inn: true, map_x: 552, map_y: 226},
  %{name: "Рифтен", description: "Город воров и теней.", region: "Скайрим", location_type: "city", danger_level: "Средняя", min_level: 5, max_level: 10, has_shop: true, has_inn: true, map_x: 813, map_y: 410},
  %{name: "Солитьюд", description: "Город-крепость, резиденция высшего Короля.", region: "Скайрим", location_type: "city", danger_level: "Высокая", min_level: 8, max_level: 15, has_shop: true, has_inn: true, map_x: 406, map_y: 47},
  %{name: "Виндхельм", description: "Северный город, покрытый снегом.", region: "Скайрим", location_type: "city", danger_level: "Средняя", min_level: 6, max_level: 12, has_shop: true, has_inn: true, map_x: 744, map_y: 150},
  %{name: "Фолкрит", description: "Маленький городок с тёмными тайнами.", region: "Скайрим", location_type: "village", danger_level: "Низкая", min_level: 3, max_level: 8, has_shop: true, has_inn: true, map_x: 425, map_y: 385},
  %{name: "Драконья Падь", description: "Древний склеп, где обитают драконы.", region: "Скайрим", location_type: "dungeon", danger_level: "Экстремальная", min_level: 10, max_level: 15, has_shop: false, has_inn: false, map_x: 870, map_y: 350},
  %{name: "Хребет Мира", description: "Снежные горы на севере.", region: "Скайрим", location_type: "wilderness", danger_level: "Высокая", min_level: 8, max_level: 14, has_shop: false, has_inn: false, map_x: 560, map_y: 160},
  %{name: "Леса Глэмориин", description: "Густые леса, полные опасностей.", region: "Скайрим", location_type: "wilderness", danger_level: "Средняя", min_level: 4, max_level: 9, has_shop: false, has_inn: false, map_x: 240, map_y: 320},
  %{name: "Долина Буревестников", description: "Тихая долина между горами.", region: "Скайрим", location_type: "wilderness", danger_level: "Средняя", min_level: 5, max_level: 10, has_shop: false, has_inn: false, map_x: 200, map_y: 500},
]

Enum.each(locations, fn attrs ->
  %Location{}
  |> Location.changeset(attrs)
  |> Repo.insert(on_conflict: :nothing)
end)

IO.puts("Seeded #{length(locations)} locations")

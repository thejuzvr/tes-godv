# Скромные стартовые вещи предысторий (docs/PLAN_CHARACTER.md). Идемпотентно по имени.
# Запуск: mix run priv/seed_origins.exs

alias TesIdle.Repo
alias TesIdle.Schemas.Item
import Ecto.Query

items = [
  %{name: "Ученическая роба", description: "Чужая роба коллегии, ещё пахнет чернилами.", icon: "🧥", equip_slot: "body", defense_bonus: 1, hp_bonus: 2},
  %{name: "Клинок ополчения", description: "Простое железо городской стражи.", icon: "🗡️", equip_slot: "weapon", attack_bonus: 2},
  %{name: "Отмычка", description: "Тонкая, гнётся. Для первой двери хватит.", icon: "🗝️", equip_slot: nil, tags: ["lockpick"]},
  %{name: "Ряса послушника", description: "Серая храмовая ряса, тёплая и безликая.", icon: "🧥", equip_slot: "body", defense_bonus: 1}
]

Enum.each(items, fn attrs ->
  exists? = Repo.exists?(from i in Item, where: i.name == ^attrs.name)

  unless exists? do
    Repo.insert!(%Item{
      name: attrs.name,
      description: attrs.description,
      item_type: "equipment",
      rarity: "common",
      icon: attrs.icon,
      weight: 1.0,
      sell_price: 5,
      tags: Map.get(attrs, :tags, ["origin"]),
      equip_slot: attrs.equip_slot,
      attack_bonus: Map.get(attrs, :attack_bonus, 0),
      defense_bonus: Map.get(attrs, :defense_bonus, 0),
      hp_bonus: Map.get(attrs, :hp_bonus, 0),
      speed_bonus: 0.0,
      reduce_hunger: 0.0,
      reduce_fatigue: 0.0,
      boost_morale: 0.0,
      soul_restore: 0.0
    })
  end
end)

IO.puts("origin items ready")

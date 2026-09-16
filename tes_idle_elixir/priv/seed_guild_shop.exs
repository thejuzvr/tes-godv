# G-3 «Лавка гильдии»: уникальные предметы + шаблон журнала покупки (идемпотентно).
# Запуск: mix run priv/seed_guild_shop.exs

alias TesIdle.Repo
alias TesIdle.Schemas.{Item, NarrativeTemplate}
import Ecto.Query

# ── Предметы лавки (поиск покупки — по name, is_active) ──────────────────────

items = [
  %{
    name: "Плащ Соратников",
    description: "Ткань вышита гербами всех, кто жертвовал на общий алтарь. +3 к защите, +10 к здоровью.",
    item_type: "equipment",
    rarity: "uncommon",
    icon: "🧥",
    weight: 2.0,
    sell_price: 30,
    tags: ["guild"],
    equip_slot: "body",
    attack_bonus: 0,
    defense_bonus: 3,
    hp_bonus: 10,
  },
  %{
    name: "Знак гильдии",
    description: "Бронзовый жетон старой гильдии. Тяжелеет с каждым общим делом. +2 к атаке.",
    item_type: "equipment",
    rarity: "uncommon",
    icon: "🏅",
    weight: 1.0,
    sell_price: 20,
    tags: ["guild"],
    equip_slot: "amulet",
    attack_bonus: 2,
    defense_bonus: 0,
    hp_bonus: 0,
  },
  %{
    name: "Эликсир Соборности",
    description: "Настой, сваренный на пепле праздничного костра. Лечит раны и придаёт ярости в бою.",
    item_type: "consumable",
    rarity: "common",
    icon: "🧪",
    weight: 1.0,
    sell_price: 10,
    tags: ["guild", "potion"],
    heal_hp: 40,
    heal_mp: 0,
    heal_sp: 30,
    buff_attack: 2,
    buff_duration_ticks: 10
  },
  # --- CD-1: расширение лавки 3 → 12 (тональная смесь: серьёзные + комичные) ---
  %{
    name: "Шлем дозорного знамени",
    description: "Выкован в честь часовых, что не спали по ночам. +7 к защите, +4 к здоровью.",
    item_type: "equipment",
    rarity: "uncommon",
    icon: "🪖",
    weight: 3.0,
    sell_price: 45,
    tags: ["guild"],
    equip_slot: "head",
    attack_bonus: 0,
    defense_bonus: 7,
    hp_bonus: 4,
  },
  %{
    name: "Сапоги тысяч вёрст",
    description: "Прошли всё: от Рифтена до Солитьюда. Стёрлись — закалились. +5 защита, +1 скорость.",
    item_type: "equipment",
    rarity: "uncommon",
    icon: "🥾",
    weight: 1.5,
    sell_price: 35,
    tags: ["guild"],
    equip_slot: "legs",
    attack_bonus: 0,
    defense_bonus: 5,
    hp_bonus: 0,
    speed_bonus: 1.0,
  },
  %{
    name: "Кольцо общего дела",
    description: "Простая медь, но каждый вклад в алтарь делает её теплее. +2 атака, +2 защита.",
    item_type: "equipment",
    rarity: "rare",
    icon: "💫",
    weight: 0.2,
    sell_price: 60,
    tags: ["guild"],
    equip_slot: "ring",
    attack_bonus: 2,
    defense_bonus: 2,
    hp_bonus: 0,
  },
  %{
    name: "Перчатки печатника",
    description: "Для тех, кто ставит подписи под великими решениями. +1 атака, +4 защита.",
    item_type: "equipment",
    rarity: "common",
    icon: "🧤",
    weight: 0.8,
    sell_price: 25,
    tags: ["guild"],
    equip_slot: "hands",
    attack_bonus: 1,
    defense_bonus: 4,
    hp_bonus: 0,
  },
  %{
    name: "Сталь основателя",
    description: "Клинок из оружия первого состава знамени. Помнит все уставы наизусть.",
    item_type: "equipment",
    rarity: "rare",
    icon: "⚔️",
    weight: 3.6,
    sell_price: 90,
    tags: ["guild"],
    equip_slot: "weapon",
    attack_bonus: 14,
    defense_bonus: 1,
    hp_bonus: 0,
  },
  %{
    name: "Реликвия казначея",
    description: "Счётная доска, превращённая в амулет. Золото слышит её издалека.",
    item_type: "equipment",
    rarity: "rare",
    icon: "🧮",
    weight: 0.5,
    sell_price: 70,
    tags: ["guild"],
    equip_slot: "amulet",
    attack_bonus: 1,
    defense_bonus: 2,
    hp_bonus: 8,
  },
  %{
    name: "Броня смотрителя алтаря",
    description: "Награда тем, кто кормит пламя. Огонь заодно и закаляет. +9 защита, +12 HP.",
    item_type: "equipment",
    rarity: "rare",
    icon: "🔥",
    weight: 6.0,
    sell_price: 110,
    tags: ["guild"],
    equip_slot: "body",
    attack_bonus: 0,
    defense_bonus: 9,
    hp_bonus: 12,
  },
  %{
    name: "Медовуха сплочения",
    description: "Пьётся залпом — дружба остаётся. Мораль +25, немного сытости.",
    item_type: "consumable",
    rarity: "common",
    icon: "🍯",
    weight: 1.0,
    sell_price: 8,
    tags: ["guild", "potion"],
    heal_hp: 10,
    heal_mp: 0,
    heal_sp: 0,
    boost_morale: 25.0,
    reduce_hunger: 10.0,
  },
  %{
    name: "Похлёбка казармы",
    description: "Рецепт с диалектом: «ешь и не спрашивай». Сытость +40, лёгкий отдых.",
    item_type: "consumable",
    rarity: "common",
    icon: "🥣",
    weight: 1.2,
    sell_price: 6,
    tags: ["guild", "food"],
    heal_hp: 8,
    heal_mp: 0,
    heal_sp: 0,
    reduce_hunger: 40.0,
    reduce_fatigue: 15.0,
  }
]

items_inserted =
  Enum.reduce(items, 0, fn attrs, acc ->
    # CD-1: any/nil вместо get_by — легаси-дубликаты имён в dev-БД
    exists =
      Repo.one(
        from i in Item, where: i.name == ^attrs.name and i.is_active == true, limit: 1
      )

    if exists do
      acc
    else
      Repo.insert!(%Item{
        name: attrs.name,
        description: attrs.description,
        item_type: attrs.item_type,
        rarity: attrs.rarity,
        icon: attrs.icon,
        weight: attrs.weight,
        sell_price: attrs.sell_price,
        is_active: true,
        tags: attrs.tags,
        heal_hp: attrs[:heal_hp] || 0,
        heal_mp: attrs[:heal_mp] || 0,
        heal_sp: attrs[:heal_sp] || 0,
        reduce_hunger: attrs[:reduce_hunger] || 0.0,
        reduce_fatigue: attrs[:reduce_fatigue] || 0.0,
        boost_morale: attrs[:boost_morale] || 0.0,
        soul_restore: attrs[:soul_restore] || 0.0,
        equip_slot: attrs[:equip_slot],
        attack_bonus: attrs[:attack_bonus] || 0,
        defense_bonus: attrs[:defense_bonus] || 0,
        hp_bonus: attrs[:hp_bonus] || 0,
        speed_bonus: attrs[:speed_bonus] || 0.0,
        buff_attack: attrs[:buff_attack] || 0,
        buff_duration_ticks: attrs[:buff_duration_ticks] || 0
      })

      acc + 1
    end
  end)

# ── Шаблон журнала покупки (идемпотентно по {template_type, text}) ───────────

templates = [
  "{hero_name} выменивает «{item}» на {points} очков гильдии — заслуги превращаются в железо.",
  "Лавка гильдии отпускает {hero_name} «{item}». {points} очков со счета не вернутся, да они и не жалко.",
  "{hero_name} забирает «{item}» из гильдейской лавки, расплатившись {points} очками и коротким кивком."
]

templates_inserted =
  Enum.reduce(templates, 0, fn text, acc ->
    exists =
      Repo.exists?(
        from t in NarrativeTemplate,
          where: t.template_type == "guild_shop_purchase" and t.text_template == ^text
      )

    if exists do
      acc
    else
      Repo.insert!(%NarrativeTemplate{
        template_type: "guild_shop_purchase",
        text_template: text,
        source: "system",
        is_active: true
      })

      acc + 1
    end
  end)

# ── CD-1: конфиг лавки (источник каталога для Game.Guilds.Shop) ───────────────
# Catalog: 12 позиций, очки 20..180 — тема знамени + тональная смесь.

catalog =
  Enum.map(items, fn attrs ->
    %{
      "name" => attrs.name,
      "points" =>
        case attrs.name do
          "Плащ Соратников" -> 60
          "Знак гильдии" -> 40
          "Эликсир Соборности" -> 20
          "Шлем дозорного знамени" -> 70
          "Сапоги тысяч вёрст" -> 45
          "Кольцо общего дела" -> 90
          "Перчатки печатника" -> 30
          "Сталь основателя" -> 180
          "Реликвия казначея" -> 100
          "Броня смотрителя алтаря" -> 150
          "Медовуха сплочения" -> 25
          "Похлёбка казармы" -> 15
          _ -> 50
        end
    }
  end)

guild_shop_cfg = Repo.get_by(TesIdle.Schemas.GameConfig, key: "guild_shop")

if guild_shop_cfg do
  guild_shop_cfg
  |> Ecto.Changeset.change(value: Jason.encode!(%{"catalog" => catalog}))
  |> Repo.update!()
else
  Repo.insert!(%TesIdle.Schemas.GameConfig{
    key: "guild_shop",
    value: Jason.encode!(%{"catalog" => catalog}),
    description: "Каталог лавки гильдии: имя предмета → цена в очках (G-3/CD-1)"
  })
end

items_total = Repo.one(from i in Item, where: i.is_active == true and fragment("? @> ARRAY[?]::varchar[]", i.tags, "guild"), select: count(i.id))
tpl_total = Repo.one(from t in NarrativeTemplate, where: t.template_type == "guild_shop_purchase", select: count(t.id))

IO.puts("seed_guild_shop: предметов +#{items_inserted} (всего #{items_total}), шаблонов +#{templates_inserted} (всего #{tpl_total}), каталог = #{length(catalog)} позиций")

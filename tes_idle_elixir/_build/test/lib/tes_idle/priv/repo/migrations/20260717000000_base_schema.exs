defmodule TesIdle.Repo.Migrations.BaseSchema do
  @moduledoc """
  Полная базовая схема проекта (зеркало реальной БД, БЕЗ колонок Фазы 0).

  Историческая справка: начальная миграция 20260716 была заглушкой
  ("таблицы уже созданы Python-бэкендом") — на чистой БД проект не поднимался.
  Эта миграция делает проект самодостаточным: CREATE TABLE IF NOT EXISTS
  на живой dev-БД — no-op, на чистой — создаёт всё.

  Порядок на чистой БД: 20260716 (заглушка) → ЭТА → 20260902130000 (Фаза 0).
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY,
      username VARCHAR NOT NULL UNIQUE,
      email VARCHAR NOT NULL UNIQUE,
      password_hash VARCHAR NOT NULL,
      is_admin BOOLEAN NOT NULL,
      is_online BOOLEAN NOT NULL,
      last_seen TIMESTAMP NOT NULL DEFAULT NOW(),
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    """)

    # Старые БД (stub 20260716) могут иметь users без этих колонок — достраиваем
    execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_online BOOLEAN NOT NULL DEFAULT false")
    execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen TIMESTAMP NOT NULL DEFAULT NOW()")
    execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMP NOT NULL DEFAULT NOW()")
    execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP NOT NULL DEFAULT NOW()")

    execute("""
    CREATE TABLE IF NOT EXISTS locations (
      id UUID PRIMARY KEY,
      name VARCHAR NOT NULL UNIQUE,
      description TEXT NOT NULL,
      region VARCHAR NOT NULL,
      location_type VARCHAR NOT NULL,
      danger_level VARCHAR NOT NULL,
      min_level INTEGER NOT NULL,
      max_level INTEGER NOT NULL,
      has_shop BOOLEAN NOT NULL,
      has_inn BOOLEAN NOT NULL,
      weather VARCHAR NOT NULL
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS items (
      id UUID PRIMARY KEY,
      name VARCHAR NOT NULL,
      description TEXT NOT NULL,
      item_type VARCHAR NOT NULL,
      rarity VARCHAR NOT NULL,
      icon VARCHAR NOT NULL,
      weight DOUBLE PRECISION NOT NULL,
      sell_price INTEGER NOT NULL,
      is_active BOOLEAN NOT NULL,
      heal_hp INTEGER NOT NULL,
      heal_mp INTEGER NOT NULL,
      heal_sp INTEGER NOT NULL,
      reduce_hunger DOUBLE PRECISION NOT NULL,
      reduce_fatigue DOUBLE PRECISION NOT NULL,
      boost_morale DOUBLE PRECISION NOT NULL,
      buff_attack INTEGER NOT NULL,
      buff_duration_ticks INTEGER NOT NULL,
      soul_restore DOUBLE PRECISION NOT NULL,
      equip_slot VARCHAR,
      attack_bonus INTEGER NOT NULL,
      defense_bonus INTEGER NOT NULL,
      hp_bonus INTEGER NOT NULL,
      speed_bonus DOUBLE PRECISION NOT NULL
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS heroes (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id),
      name VARCHAR NOT NULL,
      race VARCHAR NOT NULL,
      hero_class VARCHAR NOT NULL,
      level INTEGER NOT NULL DEFAULT 1,
      xp INTEGER NOT NULL DEFAULT 0,
      xp_to_next INTEGER NOT NULL DEFAULT 100,
      hp INTEGER NOT NULL DEFAULT 100,
      max_hp INTEGER NOT NULL DEFAULT 100,
      mp INTEGER NOT NULL DEFAULT 50,
      max_mp INTEGER NOT NULL DEFAULT 50,
      sp INTEGER NOT NULL DEFAULT 80,
      max_sp INTEGER NOT NULL DEFAULT 80,
      attack INTEGER NOT NULL DEFAULT 10,
      defense INTEGER NOT NULL DEFAULT 5,
      gold INTEGER NOT NULL DEFAULT 0,
      max_weight DOUBLE PRECISION NOT NULL DEFAULT 160.0,
      soul_energy DOUBLE PRECISION NOT NULL DEFAULT 0.0,
      max_soul_energy DOUBLE PRECISION NOT NULL DEFAULT 100.0,
      hunger DOUBLE PRECISION NOT NULL DEFAULT 20.0,
      fatigue DOUBLE PRECISION NOT NULL DEFAULT 10.0,
      morale DOUBLE PRECISION NOT NULL DEFAULT 70.0,
      mood DOUBLE PRECISION NOT NULL DEFAULT 60.0,
      mood_history TEXT NOT NULL DEFAULT '[]',
      game_day INTEGER NOT NULL DEFAULT 1,
      game_hour DOUBLE PRECISION NOT NULL DEFAULT 8.0,
      game_era VARCHAR NOT NULL DEFAULT 'Эпоха Третьего Престола',
      state VARCHAR NOT NULL DEFAULT 'exploring',
      state_data TEXT,
      location_id UUID REFERENCES locations(id),
      total_kills INTEGER NOT NULL DEFAULT 0,
      total_gold_earned INTEGER NOT NULL DEFAULT 0,
      total_play_time_seconds INTEGER NOT NULL DEFAULT 0,
      is_online BOOLEAN NOT NULL DEFAULT false,
      last_activity TIMESTAMP NOT NULL DEFAULT NOW(),
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      personality JSONB DEFAULT '{}'::jsonb
    );
    """)

    execute("CREATE INDEX IF NOT EXISTS heroes_user_id_index ON heroes(user_id);")

    execute("""
    CREATE TABLE IF NOT EXISTS inventory_items (
      id UUID PRIMARY KEY,
      hero_id UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
      item_id UUID NOT NULL REFERENCES items(id),
      quantity INTEGER NOT NULL
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS equipment (
      id UUID PRIMARY KEY,
      hero_id UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
      weapon_id UUID REFERENCES items(id),
      head_id UUID REFERENCES items(id),
      body_id UUID REFERENCES items(id),
      legs_id UUID REFERENCES items(id),
      ring_id UUID REFERENCES items(id),
      amulet_id UUID REFERENCES items(id)
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS monsters (
      id UUID PRIMARY KEY,
      name VARCHAR NOT NULL,
      description TEXT NOT NULL,
      location_id UUID REFERENCES locations(id),
      min_level INTEGER NOT NULL,
      max_level INTEGER NOT NULL,
      hp INTEGER NOT NULL,
      attack_min INTEGER NOT NULL,
      attack_max INTEGER NOT NULL,
      defense INTEGER NOT NULL,
      xp_reward INTEGER NOT NULL,
      gold_min INTEGER NOT NULL,
      gold_max INTEGER NOT NULL,
      is_active BOOLEAN NOT NULL
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS monster_loot (
      id UUID PRIMARY KEY,
      monster_id UUID NOT NULL REFERENCES monsters(id) ON DELETE CASCADE,
      item_id UUID NOT NULL REFERENCES items(id),
      drop_chance DOUBLE PRECISION NOT NULL
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS quests (
      id UUID PRIMARY KEY,
      name VARCHAR NOT NULL,
      description TEXT NOT NULL,
      difficulty VARCHAR NOT NULL,
      location_id UUID REFERENCES locations(id),
      xp_reward INTEGER NOT NULL,
      gold_reward INTEGER NOT NULL,
      steps_total INTEGER NOT NULL,
      is_active BOOLEAN NOT NULL
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS quest_steps (
      id UUID PRIMARY KEY,
      quest_id UUID NOT NULL REFERENCES quests(id) ON DELETE CASCADE,
      step_order INTEGER NOT NULL,
      description TEXT NOT NULL,
      step_type VARCHAR NOT NULL,
      target_count INTEGER NOT NULL
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS active_quests (
      id UUID PRIMARY KEY,
      hero_id UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
      quest_id UUID NOT NULL REFERENCES quests(id),
      current_step INTEGER NOT NULL,
      current_progress INTEGER NOT NULL,
      started_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS journal_entries (
      id UUID PRIMARY KEY,
      hero_id UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
      entry_type VARCHAR NOT NULL,
      text TEXT NOT NULL,
      xp_gained INTEGER NOT NULL,
      gold_gained INTEGER NOT NULL,
      item_name VARCHAR,
      monster_name VARCHAR,
      location_name VARCHAR,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    """)

    execute("CREATE INDEX IF NOT EXISTS journal_entries_hero_id_index ON journal_entries(hero_id);")

    execute("""
    CREATE TABLE IF NOT EXISTS reputations (
      id UUID PRIMARY KEY,
      hero_id UUID NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
      faction VARCHAR NOT NULL,
      value INTEGER NOT NULL,
      level VARCHAR NOT NULL
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS narrative_templates (
      id UUID PRIMARY KEY,
      template_type VARCHAR NOT NULL,
      text_template TEXT NOT NULL,
      conditions TEXT,
      variables TEXT,
      mood_min DOUBLE PRECISION,
      mood_max DOUBLE PRECISION,
      location_id UUID REFERENCES locations(id),
      is_active BOOLEAN NOT NULL,
      source VARCHAR NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS suggestions (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id),
      suggestion_type VARCHAR NOT NULL,
      title VARCHAR NOT NULL,
      content TEXT NOT NULL,
      status VARCHAR NOT NULL,
      admin_comment TEXT,
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      reviewed_at TIMESTAMP
    );
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS game_configs (
      id UUID PRIMARY KEY,
      key VARCHAR NOT NULL UNIQUE,
      value TEXT NOT NULL,
      description TEXT NOT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    """)
  end

  def down do
    # Разрушение базовой схемы не выполняем — данные дороже.
  end
end

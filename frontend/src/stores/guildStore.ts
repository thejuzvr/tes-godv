// Гильдии (G-0): каркас — лендинг со списком, создание, шапка + состав
export interface GuildSummary {
  id: string
  name: string
  motto: string | null
  emblem: string
  level: number
  policy: string
  member_count: number
}

export interface MyGuild {
  guild_id: string
  name: string
  emblem: string
  role: string
  user_id?: string
}

export interface GuildBuff {
  xp_mult: number
  attack_flat: number
  hp_flat: number
  level?: number
}

export interface GuildDetail {
  guild: {
    id: string
    name: string
    motto: string | null
    emblem: string
    description: string | null
    level: number
    exp: number
    exp_to_next?: number
    max_level?: number
    policy: string
    buff?: GuildBuff
  }
  members: GuildMemberRow[]
  offerings?: GuildOfferingRow[]
  my_altar?: {
    points: number
    contributed: number
    points_today: number
    daily_cap: number
  } | null
  treasury?: GuildTreasury
}

export interface GuildTreasury {
  amount: number
  log?: { kind: string; amount: number; balance_after: number }[]
  feast_cost: number
  feast_active: boolean
  boost_until: string | null
  my_can_feast: boolean
}

export interface GuildMemberRow {
  user_id: string
  username: string
  role: string
  points: number
  contributed: number
  joined_at: string
}

export interface GuildOfferingRow {
  username: string
  amount: number
  points: number
  inserted_at: string
}

// Гильдии (G-2): чат
export interface GuildChatMessage {
  id: string
  user_id: string | null
  username: string
  body: string
  kind: string
  inserted_at: string
}

export const GUILD_EMBLEMS = ["🛡️", "🐺", "🐉", "🌙", "⚔️", "🔥", "🕯️", "🦅"] as const

export const GUILD_POLICY_RU: Record<string, string> = {
  open: "Открытая",
  request: "По заявке",
  invite: "По приглашению",
}

export const GUILD_ROLE_RU: Record<string, string> = {
  leader: "Лидер",
  officer: "Офицер",
  member: "Участник",
}

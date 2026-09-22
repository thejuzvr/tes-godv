import { create } from "zustand"

export interface Location {
  id: string
  name: string
  description: string | null
  region: string
  location_type: string
  danger_level: string
  min_level: number
  max_level: number
  has_shop: boolean
  has_inn: boolean
  weather: string
}

export interface WorldEvent {
  id: string
  type: string
  name: string
  desc: string
  location_id: string | null
  ttl: number
}

// C-1 «Часовня Девяти»: публичное резюме стройки из снапшота мира
export interface Construction {
  project: string
  stage: string
  stage_index: number
  stages_total: number
  collected: number
  target: number
  progress: number
  top_donors: { name: string; gold: number }[]
  history: { name: string }[]
}

export interface World {
  day: number
  tick: number
  season: string
  weather: Record<string, string>
  prices: Record<string, Record<string, number>>
  density: Record<string, number>
  factions: Record<string, string[]>
  relations: Record<string, number>
  wars: string[]
  events: WorldEvent[]
  construction?: Construction
}

export interface Pet {  id: string
  species: "wolf" | "owl" | "cat" | "lizard"
  name: string
  mood: number
  hunger: number
  loyalty: number
  status: "active" | "cooldown" | "gone"
  revive_at: string | null
}

export interface Hero {
  id: string
  name: string
  race: string
  hero_class: string
  origin?: string | null
  origin_label?: string | null
  dossier?: string
  soul_sparks?: number
  level: number
  xp: number
  xp_to_next: number
  hp: number
  max_hp: number
  mp: number
  max_mp: number
  sp: number
  max_sp: number
  gold: number
  attack: number
  defense: number
  state: string
  state_data: string | null
  hunger: number
  fatigue: number
  morale: number
  mood: number
  mood_history: number[]
  game_day: number
  game_hour: number
  game_era: string
  location_id: string | null
  location: Location | null
  total_kills: number
  total_gold_earned: number
  total_play_time_seconds: number
  soul_energy: number
  max_soul_energy: number
  pets?: Pet[]
  bounty?: number
  skills?: Record<"fishing" | "gathering" | "mining" | "stealth" | "lockpicking", number>
  activity?: {
    kind: string
    phase?: string
    ticks_left: number
    total_ticks: number
    ticks_done: number
    target_name?: string | null
  } | null
}

interface JournalEntry {
  id: string
  entry_type: string
  text: string
  xp_gained: number
  gold_gained: number
  item_name: string | null
  monster_name: string | null
  location_name: string | null
  chapter: number | null
  chapter_title: string | null
  motive: string | null
  created_at: string
}

interface GameState {
  hero: Hero | null
  journal: JournalEntry[]
  journalCount: number
  isAuthenticated: boolean
  isLoading: boolean
  isAdmin: boolean
  wsConnected: boolean
  onlineCount: number
  world: World | null

  setHero: (hero: Hero | null) => void
  setWorld: (world: World | null) => void
  setJournal: (journal: JournalEntry[]) => void
  addJournalEntry: (entry: JournalEntry) => void
  setJournalCount: (count: number) => void
  setAuthenticated: (value: boolean) => void
  setLoading: (value: boolean) => void
  setAdmin: (value: boolean) => void
  setWsConnected: (value: boolean) => void
  setOnlineCount: (count: number) => void
  logout: () => void
}

export const useGameStore = create<GameState>((set) => ({
  hero: null,
  journal: [],
  journalCount: 0,
  isAuthenticated: !!localStorage.getItem("token"),
  isLoading: false,
  isAdmin: false,
  wsConnected: false,
  onlineCount: 0,
  world: null,

  setHero: (hero) => set({ hero }),
  setWorld: (world) => set({ world }),
  setJournal: (journal) => set({ journal }),
  addJournalEntry: (entry) =>
    set((state) => {
      // Dedup: check by id (string comparison) or text+created_at
      const entryId = String(entry.id || "")
      const exists = state.journal.some(
        (e) => (entryId && String(e.id || "") === entryId) ||
               (e.text === entry.text && String(e.created_at) === String(entry.created_at))
      )
      if (exists) return state
      return {
        journal: [entry, ...state.journal].slice(0, 200),
        journalCount: state.journalCount + 1,
      }
    }),
  setJournalCount: (journalCount) => set({ journalCount }),
  setAuthenticated: (isAuthenticated) => set({ isAuthenticated }),
  setLoading: (isLoading) => set({ isLoading }),
  setAdmin: (isAdmin) => set({ isAdmin }),
  setWsConnected: (wsConnected) => set({ wsConnected }),
  setOnlineCount: (onlineCount) => set({ onlineCount }),
  logout: () => {
    localStorage.removeItem("token")
    set({ hero: null, journal: [], isAuthenticated: false, isAdmin: false, wsConnected: false })
  },
}))

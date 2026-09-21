import { useState } from "react"

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

interface JournalPanelProps {
  entries: JournalEntry[]
  count: number
}

/* ─── Семантические категории хроники: точные типы + эвристика имён ─── */
const CATEGORY_RULES: { key: string; label: string; types: string[]; hints: string[] }[] = [
  { key: "combat", label: "Бой", types: ["combat", "combat_result", "combat_defeat", "enemy_ambush", "hero_victory", "spot_bandits"], hints: ["ambush", "victory", "defeat", "combat", "bandit", "attack"] },
  { key: "loot", label: "Лут", types: ["loot", "find_loot", "collect_herbs"], hints: ["loot", "collect", "treasure", "herb"] },
  { key: "travel", label: "Путь", types: ["travel", "travel_road", "travel_shortcut", "leave_city", "enter_city", "cross_bridge"], hints: ["travel", "city", "bridge", "road", "gate", "path"] },
  { key: "rest", label: "Отдых", types: ["rest", "rest_by_fire", "sleep_in_inn", "watch_sunset", "smell_flowers", "hear_river", "hear_birds", "feel_confident"], hints: ["rest", "sleep", "sunset", "flowers", "fire", "inn"] },
  { key: "social", label: "Люди", types: ["meet_merchant", "find_abandoned_cart", "find_shrine", "socialize"], hints: ["merchant", "cart", "shrine", "talk", "meet"] },
  { key: "world_news", label: "📡 Новости", types: ["world_news"], hints: [] },
]

function classify(entry: JournalEntry): string {
  const t = entry.entry_type || ""
  for (const rule of CATEGORY_RULES) {
    if (rule.types.includes(t)) return rule.key
  }
  for (const rule of CATEGORY_RULES) {
    if (rule.hints.some((h) => t.includes(h))) return rule.key
  }
  return "other"
}

/* Дедупликация: одна запись может прийти и по REST, и по WS-пушу */
function dedupe(entries: JournalEntry[]): JournalEntry[] {
  const seen = new Set<string>()
  const out: JournalEntry[] = []
  for (const e of entries) {
    const id = String(e?.id ?? "")
    if (!id || seen.has(id)) continue
    seen.add(id)
    out.push(e)
  }
  return out
}

/* ─── Группировка по главам (S-3) ── */
function groupByChapters(entries: JournalEntry[]): { key: string; title: string | null; entries: JournalEntry[] }[] {
  const groups: { key: string; title: string | null; entries: JournalEntry[] }[] = []
  for (const entry of entries) {
    const title = entry.chapter_title || null
    const key = title || `legacy-${entry.chapter ?? "x"}`
    const last = groups[groups.length - 1]
    if (last && last.key === key) {
      last.entries.push(entry)
    } else {
      groups.push({ key, title, entries: [entry] })
    }
  }
  return groups
}

/* ─── Чистый таймстемп: «Сегодня, 16:23» / «03.09, 16:23» ─── */
function entryTime(entry: JournalEntry): string {
  const raw = typeof entry.created_at === "string" && !entry.created_at.includes("Z") && !entry.created_at.includes("+") ? entry.created_at + "Z" : entry.created_at
  const d = new Date(raw)
  const hhmm = d.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" })
  const now = new Date()
  if (d.getDate() === now.getDate() && d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()) {
    return `Сегодня, ${hhmm}`
  }
  const ddmm = d.toLocaleDateString("ru-RU", { day: "2-digit", month: "2-digit" })
  return `${ddmm}, ${hhmm}`
}

/* ─── Journal Panel — хроника-манускрипт: главы, категории, мотивы на полях ───
   Фильтрация считается на каждом рендере (без useMemo): 200 записей — копейки,
   а никакой шанс на протухший мем при HMR/WS-обновлениях. */
export function JournalPanel({ entries, count }: JournalPanelProps) {
  const [filter, setFilter] = useState<string | null>(null)

  const unique = dedupe(entries)
  const filtered = filter ? unique.filter((e) => classify(e) === filter) : unique

  // Категории, реально присутствующие в загруженных записях
  const present = new Set(unique.map((e) => classify(e)))
  const categories = CATEGORY_RULES.filter((r) => present.has(r.key))
  const activeCategoryExists = filter === null || categories.some((c) => c.key === filter)

  const chapterGroups = groupByChapters(filtered)

  return (
    <div className="panel journal-panel fantasy-window">
      <div className="panel-header">
        <div className="flex items-center gap-2">
          <span className="panel-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg>
          </span>
          Хроника героя
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)", fontWeight: 400, textTransform: "none", letterSpacing: 0 }}>{count} записей</span>
        </div>
      </div>
      <div className="tabs">
        <button type="button" className={`tab ${filter === null ? "active" : ""}`} onClick={() => setFilter(null)}>Все</button>
        {categories.map((c) => (
          <button type="button" key={c.key} className={`tab ${filter === c.key ? "active" : ""}`} onClick={() => setFilter(c.key)}>
            {c.label}
          </button>
        ))}
      </div>
      <div className="panel-body">
        {filtered.length === 0 ? (
          <div style={{ textAlign: "center", color: "var(--muted)", padding: "32px 0", fontSize: "var(--text-sm)", lineHeight: 1.6 }}>
            {filter !== null && activeCategoryExists
              ? "В этой категории записей нет."
              : "Записей пока нет — герой ещё ничего не прожил."}
          </div>
        ) : (
          chapterGroups.map((group, gi) => (
            <div key={`${gi}-${group.key}`}>
              {group.title && (
                <div className="gilded-divider" style={{ margin: "22px 0 12px" }}>
                  <span style={{ color: "var(--accent)", fontSize: 10 }}>◆</span>
                  <span
                    style={{
                      fontFamily: "var(--font-display)",
                      fontStyle: "italic",
                      fontWeight: 700,
                      fontSize: 16,
                      color: "var(--accent)",
                      whiteSpace: "nowrap",
                      padding: "0 8px",
                    }}
                  >
                    {group.title}
                  </span>
                  <span style={{ color: "var(--accent)", fontSize: 10 }}>◆</span>
                </div>
              )}
              {group.entries.map((entry) => (
                <div key={entry.id} className={`journal-entry anim-entry ${classify(entry)} ${entry.entry_type === "world_news" ? "world_news" : ""}`}>
                  <div className="journal-time">{entryTime(entry)}</div>
                  <div className="journal-text">{entry.text}</div>
                  {entry.motive && (
                    <div className="journal-motive">Решение: {entry.motive}</div>
                  )}
                  {(entry.gold_gained > 0 || entry.xp_gained > 0) && (
                    <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
                      {entry.gold_gained > 0 && <span className="loot-tag">💰 +{entry.gold_gained} золота</span>}
                      {entry.xp_gained > 0 && <span className="combat-tag">⚔️ +{entry.xp_gained} XP</span>}
                    </div>
                  )}
                </div>
              ))}
            </div>
          ))
        )}
      </div>
    </div>
  )
}

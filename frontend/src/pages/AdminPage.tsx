import { useState, useEffect, useCallback } from "react"
import { api } from "@/lib/api"
import { formatNumber, formatDate } from "@/lib/utils"
import { VAR_GROUPS, TEMPLATE_TYPES, TEMPLATE_TYPE_GROUPS } from "@/components/narrativeData"

/* ─── Narrative helpers (Библиотека) ────────────────── */
// Превью шаблона: подстановка примеров из словника; неизвестные переменные остаются видимыми
function renderPreview(text: string): string {
  const samples: Record<string, string> = {}
  for (const g of VAR_GROUPS) for (const v of g.vars) samples[v.var.replace(/[{}]/g, "")] = v.example
  return text.replace(/\{(\w+)\}/g, (match, key: string) => samples[key] ?? match)
}

/* ─── Tab system ────────────────────────────────────── */
const tabs = [
  { key: "overview", label: "Обзор" },
  { key: "users", label: "Пользователи" },
  { key: "heroes", label: "Герои" },
  { key: "narratives", label: "Нарративы" },
  { key: "narrative-analytics", label: "Аналитика нарративов" },
  { key: "moderation", label: "Модерация" },
  { key: "suggestions", label: "Предложения" },
  { key: "simulation", label: "Симуляция" },
  { key: "tests", label: "Тесты" },
  { key: "config", label: "Конфиг" },
  { key: "backup", label: "Бэкап" },
]

/* ─── Narrative filter options (shared) ─────────────── */
const FILTER_OPTIONS = [
  { k: "", l: "Все" },
  // Combat events
  { k: "hero_victory", l: "Герой: Победа" },
  { k: "hero_defeat", l: "Герой: Поражение" },
  { k: "enemy_ambush", l: "Засада" },
  { k: "spot_bandits", l: "Бандиты" },
  { k: "hear_wolves", l: "Вой волков" },
  // Travel events
  { k: "leave_city", l: "Покинуть город" },
  { k: "travel_road", l: "Путешествие: Дорога" },
  { k: "travel_shortcut", l: "Короткий путь" },
  { k: "cross_bridge", l: "Пересечь мост" },
  { k: "enter_city", l: "Войти в город" },
  { k: "bad_weather", l: "Непогода" },
  // Discovery events
  { k: "discover_ruin", l: "Руины" },
  { k: "discover_cave", l: "Пещера" },
  { k: "find_shrine", l: "Святилище" },
  { k: "find_abandoned_cart", l: "Брошенная телега" },
  { k: "notice_tracks", l: "Следы (свежие)" },
  { k: "hear_river", l: "Шум реки" },
  { k: "find_tracks", l: "Следы" },
  { k: "hear_birds", l: "Пениептиц" },
  { k: "smell_flowers", l: "Цветы" },
  // Rest events
  { k: "sleep_in_inn", l: "Сон в таверне" },
  { k: "rest_by_fire", l: "Отдых у костра" },
  { k: "watch_sunset", l: "Закат" },
  // Social events
  { k: "meet_merchant", l: "Встретить торговца" },
  { k: "learn_rumors", l: "Сплетни" },
  { k: "hear_song", l: "Песня" },
  { k: "shelter_from_storm", l: "Укрыться от грозы" },
  // Loot events
  { k: "find_loot", l: "Найти добычу" },
  { k: "discover_treasure", l: "Сокровище" },
  // Memory events
  { k: "remember_defeat", l: "Вспомнить поражение" },
  { k: "feel_confident", l: "Уверенность" },
  { k: "avoid_danger", l: "Избежать опасности" },
  { k: "search_danger", l: "Искать опасность" },
  { k: "collect_herbs", l: "Сбор трав" },
  // Legacy + God events
  { k: "combat_start", l: "Бой: Начало" },
  { k: "combat_result", l: "Бой: Победа" },
  { k: "combat_defeat", l: "Бой: Поражение" },
  { k: "explore", l: "Исследование" },
  { k: "rest", l: "Отдых" },
  { k: "loot", l: "Лут" },
  { k: "shop", l: "Торговля" },
  { k: "social", l: "Общение" },
  { k: "travel", l: "Путешествие" },
  { k: "equip", l: "Экипировка" },
  { k: "death", l: "Смерть" },
  { k: "thought", l: "Мысли" },
  { k: "generic_action", l: "Действие" },
  { k: "god_encourage", l: "Бог: Вдохновить" },
  { k: "god_punish", l: "Бог: Наказать" },
  { k: "god_heal", l: "Бог: Исцелить" },
  { k: "god_direct", l: "Бог: Направить" },
  { k: "god_quest", l: "Бог: Задание" },
  { k: "god_weather", l: "Бог: Погода" },
]

// Полный список для select формы: события из словника + legacy-типы из фильтра (без дубликатов)
const TEMPLATE_TYPE_SET = new Set(TEMPLATE_TYPES.map((t) => t.id))
const FORM_TYPES = [
  ...TEMPLATE_TYPES,
  ...FILTER_OPTIONS.filter((f) => f.k && !TEMPLATE_TYPE_SET.has(f.k)).map((f) => ({ id: f.k, label: f.l })),
]

/* ─── Overview Panel ────────────────────────────────── */
function OverviewPanel() {
  const [stats, setStats] = useState<any>(null)
  const [loops, setLoops] = useState<any>(null)

  useEffect(() => {
    api.adminStats().then(setStats).catch(() => {})
    api.adminLoops().then(setLoops).catch(() => {})
  }, [])

  if (!stats) return <div style={{ color: "var(--muted)", padding: 32 }}>Загрузка…</div>

  const cards = [
    { label: "Пользователи", value: stats.users, icon: "👤" },
    { label: "Герои", value: stats.heroes, icon: "⚔️" },
    { label: "Записи дневника", value: stats.journal_entries, icon: "📖" },
    { label: "Шаблоны нарративов", value: stats.narrative_templates, icon: "📝" },
    { label: "Монстры", value: stats.monsters, icon: "👹" },
    { label: "Предметы", value: stats.items, icon: "📦" },
    { label: "Активные циклы", value: stats.active_loops, icon: "🔄" },
  ]

  return (
    <div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))", gap: "var(--space-3)", marginBottom: "var(--space-4)" }}>
        {cards.map((c) => (
          <div key={c.label} className="panel">
            <div className="panel-body" style={{ textAlign: "center" }}>
              <div style={{ fontSize: 24, marginBottom: "var(--space-1)" }}>{c.icon}</div>
              <div style={{ fontFamily: "var(--font-mono)", fontWeight: 700, fontSize: "var(--text-xl)" }}>{formatNumber(c.value)}</div>
              <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>{c.label}</div>
            </div>
          </div>
        ))}
      </div>

      {/* SQLAdmin Link */}
      <a href="/admin/" target="_blank" rel="noopener noreferrer"
        style={{ display: "inline-flex", alignItems: "center", gap: "var(--space-2)", padding: "8px 16px", background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--radius-lg)", fontSize: "var(--text-sm)", color: "var(--fg)", textDecoration: "none", transition: "all 150ms", marginBottom: "var(--space-4)" }}>
        <span style={{ fontSize: 18 }}>🗄️</span>
        Открыть CRUD-панель (SQLAdmin)
      </a>

      {loops && (
        <div className="panel">
          <div className="panel-header">Игровые циклы</div>
          <div className="panel-body">
            <div style={{ marginBottom: "var(--space-2)" }}>
              <span style={{ fontFamily: "var(--font-mono)", fontWeight: 600 }}>{loops.count}</span> активных циклов
            </div>
            <button onClick={() => api.adminRestartLoops().then(() => api.adminLoops().then(setLoops))}
              style={{ padding: "6px 14px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: "pointer" }}>
              Перезапустить все циклы
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

/* ─── Users Panel ───────────────────────────────────── */
function UsersPanel() {
  const [data, setData] = useState<any>(null)
  const [page, setPage] = useState(1)

  const load = useCallback(() => {
    api.adminUsers(page).then(setData).catch(() => {})
  }, [page])

  useEffect(() => { load() }, [load])

  if (!data) return <div style={{ color: "var(--muted)", padding: 32 }}>Загрузка…</div>

  return (
    <div className="panel">
      <div className="panel-header">
        Пользователи
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)", fontWeight: 400, textTransform: "none", letterSpacing: 0 }}>{data.total} всего</span>
      </div>
      <div className="panel-body" style={{ padding: 0 }}>
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "var(--text-sm)" }}>
          <thead>
            <tr style={{ borderBottom: "1px solid var(--border)" }}>
              <th style={{ padding: "var(--space-2) var(--space-4)", textAlign: "left", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", color: "var(--muted)" }}>Имя</th>
              <th style={{ padding: "var(--space-2) var(--space-4)", textAlign: "left", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", color: "var(--muted)" }}>Email</th>
              <th style={{ padding: "var(--space-2) var(--space-4)", textAlign: "left", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", color: "var(--muted)" }}>Роль</th>
              <th style={{ padding: "var(--space-2) var(--space-4)", textAlign: "left", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", color: "var(--muted)" }}>Действия</th>
            </tr>
          </thead>
          <tbody>
            {data.users.map((u: any) => (
              <tr key={u.id} style={{ borderBottom: "1px solid var(--border)" }}>
                <td style={{ padding: "var(--space-2) var(--space-4)" }}>{u.username}</td>
                <td style={{ padding: "var(--space-2) var(--space-4)", color: "var(--muted)" }}>{u.email}</td>
                <td style={{ padding: "var(--space-2) var(--space-4)" }}>
                  <span style={{ padding: "2px 8px", borderRadius: "var(--radius-pill)", fontSize: 11, fontFamily: "var(--font-mono)",
                    background: u.is_admin ? "color-mix(in oklab, var(--epic), transparent 85%)" : "color-mix(in oklab, var(--fg), transparent 90%)",
                    color: u.is_admin ? "var(--epic)" : "var(--muted)" }}>
                    {u.is_admin ? "Админ" : "Игрок"}
                  </span>
                </td>
                <td style={{ padding: "var(--space-2) var(--space-4)" }}>
                  <button onClick={() => api.adminSetAdmin(u.id, !u.is_admin).then(load)}
                    style={{ padding: "4px 10px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--border)", background: "var(--panel-bg)", cursor: "pointer" }}>
                    {u.is_admin ? "Снять админа" : "Сделать админом"}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {data.total > data.per_page && (
        <div style={{ display: "flex", justifyContent: "center", gap: "var(--space-2)", padding: "var(--space-3)" }}>
          <button onClick={() => setPage(Math.max(1, page - 1))} disabled={page === 1}
            style={{ padding: "4px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--border)", background: page === 1 ? "transparent" : "var(--panel-bg)", cursor: page === 1 ? "default" : "pointer" }}>Назад</button>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)", display: "flex", alignItems: "center" }}>{page}</span>
          <button onClick={() => setPage(page + 1)} disabled={data.users.length < data.per_page}
            style={{ padding: "4px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--border)", background: data.users.length < data.per_page ? "transparent" : "var(--panel-bg)", cursor: data.users.length < data.per_page ? "default" : "pointer" }}>Вперёд</button>
        </div>
      )}
    </div>
  )
}

/* ─── Heroes Panel ──────────────────────────────────── */
function HeroesPanel() {
  const [data, setData] = useState<any>(null)
  const [page, setPage] = useState(1)
  const [selected, setSelected] = useState<any>(null)

  const load = useCallback(() => {
    api.adminHeroes(page).then(setData).catch(() => {})
  }, [page])

  useEffect(() => { load() }, [load])

  const viewHero = async (id: string) => {
    const d = await api.adminHero(id)
    setSelected(d)
  }

  if (!data) return <div style={{ color: "var(--muted)", padding: 32 }}>Загрузка…</div>

  return (
    <div>
      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">
          Герои
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)", fontWeight: 400, textTransform: "none", letterSpacing: 0 }}>{data.total} всего</span>
        </div>
        <div className="panel-body" style={{ padding: 0 }}>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "var(--text-sm)" }}>
            <thead>
              <tr style={{ borderBottom: "1px solid var(--border)" }}>
                <th style={{ padding: "var(--space-2) var(--space-4)", textAlign: "left", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", color: "var(--muted)" }}>Имя</th>
                <th style={{ padding: "var(--space-2) var(--space-4)", textAlign: "left", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", color: "var(--muted)" }}>Уровень</th>
                <th style={{ padding: "var(--space-2) var(--space-4)", textAlign: "left", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", color: "var(--muted)" }}>Состояние</th>
                <th style={{ padding: "var(--space-2) var(--space-4)", textAlign: "left", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", color: "var(--muted)" }}>HP</th>
                <th style={{ padding: "var(--space-2) var(--space-4)", textAlign: "left", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", color: "var(--muted)" }}>Золото</th>
                <th style={{ padding: "var(--space-2) var(--space-4)", textAlign: "left", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", color: "var(--muted)" }}>Убийства</th>
                <th style={{ padding: "var(--space-2) var(--space-4)", textAlign: "left", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", color: "var(--muted)" }}>Действия</th>
              </tr>
            </thead>
            <tbody>
              {data.heroes.map((h: any) => (
                <tr key={h.id} style={{ borderBottom: "1px solid var(--border)", cursor: "pointer" }} onClick={() => viewHero(h.id)}>
                  <td style={{ padding: "var(--space-2) var(--space-4)", fontWeight: 500 }}>{h.name}</td>
                  <td style={{ padding: "var(--space-2) var(--space-4)", fontFamily: "var(--font-mono)" }}>{h.level}</td>
                  <td style={{ padding: "var(--space-2) var(--space-4)" }}>
                    <span style={{ padding: "2px 8px", borderRadius: "var(--radius-pill)", fontSize: 11, fontFamily: "var(--font-mono)",
                      background: h.state === "dead" ? "color-mix(in oklab, var(--danger), transparent 85%)" : "color-mix(in oklab, var(--success), transparent 85%)",
                      color: h.state === "dead" ? "var(--danger)" : "var(--success)" }}>
                      {h.state}
                    </span>
                  </td>
                  <td style={{ padding: "var(--space-2) var(--space-4)", fontFamily: "var(--font-mono)" }}>{h.hp}/{h.max_hp}</td>
                  <td style={{ padding: "var(--space-2) var(--space-4)", fontFamily: "var(--font-mono)" }}>{formatNumber(h.gold)}</td>
                  <td style={{ padding: "var(--space-2) var(--space-4)", fontFamily: "var(--font-mono)" }}>{h.total_kills}</td>
                  <td style={{ padding: "var(--space-2) var(--space-4)" }}>
                    <div style={{ display: "flex", gap: "var(--space-1)" }} onClick={(e) => e.stopPropagation()}>
                      <button onClick={() => api.adminForceTick(h.id).then(load)} title="Тик"
                        style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--border)", background: "var(--panel-bg)", cursor: "pointer" }}>⚡</button>
                      <button onClick={() => api.adminResetHero(h.id).then(load)} title="Сброс"
                        style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--border)", background: "var(--panel-bg)", cursor: "pointer" }}>🔄</button>
                      <button onClick={() => { if (confirm(`Удалить ${h.name}?`)) api.adminDeleteHero(h.id).then(load) }} title="Удалить"
                        style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--danger)", background: "transparent", color: "var(--danger)", cursor: "pointer" }}>✕</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {data.total > data.per_page && (
          <div style={{ display: "flex", justifyContent: "center", gap: "var(--space-2)", padding: "var(--space-3)" }}>
            <button onClick={() => setPage(Math.max(1, page - 1))} disabled={page === 1}
              style={{ padding: "4px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--border)", background: page === 1 ? "transparent" : "var(--panel-bg)", cursor: page === 1 ? "default" : "pointer" }}>Назад</button>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)", display: "flex", alignItems: "center" }}>{page}</span>
            <button onClick={() => setPage(page + 1)} disabled={data.heroes.length < data.per_page}
              style={{ padding: "4px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--border)", background: data.heroes.length < data.per_page ? "transparent" : "var(--panel-bg)", cursor: data.heroes.length < data.per_page ? "default" : "pointer" }}>Вперёд</button>
          </div>
        )}
      </div>

      {selected && (
        <div className="panel">
          <div className="panel-header">
            Детали: {selected.hero.name}
            <button onClick={() => setSelected(null)} style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--border)", background: "var(--panel-bg)", cursor: "pointer" }}>Закрыть</button>
          </div>
          <div className="panel-body">
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: "var(--space-3)", marginBottom: "var(--space-3)" }}>
              <div><span style={{ color: "var(--muted)", fontSize: "var(--text-xs)" }}>Раса:</span> {selected.hero.race}</div>
              <div><span style={{ color: "var(--muted)", fontSize: "var(--text-xs)" }}>Класс:</span> {selected.hero.hero_class}</div>
              <div><span style={{ color: "var(--muted)", fontSize: "var(--text-xs)" }}>XP:</span> {selected.hero.xp}/{selected.hero.xp_to_next}</div>
              <div><span style={{ color: "var(--muted)", fontSize: "var(--text-xs)" }}>Атака:</span> {selected.hero.attack}</div>
              <div><span style={{ color: "var(--muted)", fontSize: "var(--text-xs)" }}>Защита:</span> {selected.hero.defense}</div>
              <div><span style={{ color: "var(--muted)", fontSize: "var(--text-xs)" }}>Время:</span> {Math.floor(selected.hero.total_play_time_seconds / 3600)}ч</div>
              <div><span style={{ color: "var(--muted)", fontSize: "var(--text-xs)" }}>Голод:</span> {Math.round(selected.hero.hunger)}%</div>
              <div><span style={{ color: "var(--muted)", fontSize: "var(--text-xs)" }}>Усталость:</span> {Math.round(selected.hero.fatigue)}%</div>
              <div><span style={{ color: "var(--muted)", fontSize: "var(--text-xs)" }}>Мораль:</span> {Math.round(selected.hero.morale)}%</div>
            </div>
            {selected.recent_journal.length > 0 && (
              <div>
                <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontFamily: "var(--font-mono)", textTransform: "uppercase", marginBottom: "var(--space-2)" }}>Последние записи:</div>
                {selected.recent_journal.map((e: any, i: number) => (
                  <div key={i} style={{ fontSize: "var(--text-xs)", color: "var(--muted)", padding: "var(--space-1) 0", borderBottom: "1px solid var(--border)" }}>
                    <span style={{ fontFamily: "var(--font-mono)" }}>[{e.type}]</span> {e.text}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

/* ─── Narrative Analytics Panel (A-2) ───────────────── */
function NarrativeAnalyticsPanel() {
  const [data, setData] = useState<any>(null)
  const [error, setError] = useState("")
  const [loading, setLoading] = useState(true)

  const loadUsage = useCallback(() => {
    api.adminNarrativeUsage(30)
      .then(setData)
      .catch(() => setError("Не удалось загрузить аналитику"))
      .finally(() => setLoading(false))
  }, [])

  useEffect(() => { loadUsage() }, [loadUsage])

  if (loading) return <div style={{ color: "var(--muted)", padding: 32 }}>Загрузка…</div>
  if (error) return <div style={{ color: "var(--danger)", padding: 32 }}>{error}</div>
  if (!data) return null

  const maxDay = Math.max(1, ...data.daily_volume.map((d: any) => d.count))

  return (
    <div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))", gap: "var(--space-3)", marginBottom: "var(--space-4)" }}>
        {[
          { label: "Записей журнала", value: data.totals.total },
          { label: "Героев писали", value: data.totals.heroes },
          { label: "Типов в журнале", value: data.totals.types },
          { label: "Мёртвых шаблонов", value: data.unused_template_types.length },
        ].map((c) => (
          <div key={c.label} className="panel">
            <div className="panel-body" style={{ textAlign: "center" }}>
              <div style={{ fontFamily: "var(--font-mono)", fontWeight: 700, fontSize: "var(--text-xl)" }}>{formatNumber(c.value)}</div>
              <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>{c.label}</div>
            </div>
          </div>
        ))}
      </div>

      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">Объём по дням (14 дней)</div>
        <div className="panel-body" style={{ display: "flex", alignItems: "flex-end", gap: 4, height: 90 }}>
          {data.daily_volume.length === 0 && <span style={{ color: "var(--muted)", fontSize: "var(--text-sm)" }}>Записей нет</span>}
          {data.daily_volume.map((d: any) => (
            <div key={d.day} title={`${d.day.slice(0, 10)}: ${d.count}`}
              style={{ flex: 1, height: `${Math.max(6, (d.count / maxDay) * 100)}%`, background: "var(--accent)", borderRadius: "var(--radius-sm)", minWidth: 8 }} />
          ))}
        </div>
      </div>

      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">Использование типов <span style={{ color: "var(--muted)", fontSize: "var(--text-xs)" }}>· тонкие первыми · ⚠ меньше 5 записей</span></div>
        <div className="panel-body" style={{ padding: 0 }}>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "var(--text-sm)" }}>
            <thead>
              <tr style={{ textAlign: "left", color: "var(--muted)", borderBottom: "1px solid var(--border)" }}>
                <th style={{ padding: "8px 12px" }}>Тип</th>
                <th style={{ padding: "8px 12px" }}>Записей</th>
                <th style={{ padding: "8px 12px" }}>Ср. длина</th>
                <th style={{ padding: "8px 12px" }}>Последний раз</th>
              </tr>
            </thead>
            <tbody>
              {data.type_usage.map((t: any) => {
                const thin = t.count < 5
                return (
                  <tr key={t.entry_type} style={{ borderBottom: "1px solid var(--border)" }}>
                    <td style={{ padding: "8px 12px", fontFamily: "var(--font-mono)", color: thin ? "var(--warn)" : undefined }}>
                      {thin ? "⚠ " : ""}{t.entry_type}
                    </td>
                    <td style={{ padding: "8px 12px", fontFamily: "var(--font-mono)" }}>{t.count}</td>
                    <td style={{ padding: "8px 12px", fontFamily: "var(--font-mono)" }}>{t.avg_length ?? "—"}</td>
                    <td style={{ padding: "8px 12px", color: "var(--muted)" }}>{formatDate(t.last_seen)}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      </div>

      <div className="panel">
        <div className="panel-header">Мёртвые шаблоны <span style={{ color: "var(--muted)", fontSize: "var(--text-xs)" }}>· активные типы без записей журнала за 30 дней</span></div>
        <div className="panel-body">
          {data.unused_template_types.length === 0 ? (
            <span style={{ color: "var(--muted)", fontSize: "var(--text-sm)" }}>Все активные типы используются</span>
          ) : (
            <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--space-2)" }}>
              {data.unused_template_types.map((t: string) => (
                <span key={t} style={{ padding: "4px 10px", background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)" }}>{t}</span>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

/* ─── Narratives Panel (Библиотека) ─────────────────── */
function NarrativesPanel() {
  const [data, setData] = useState<any>(null)
  const [stats, setStats] = useState<any>(null)
  const [page, setPage] = useState(1)
  const [typeFilter, setTypeFilter] = useState("")
  const [sourceFilter, setSourceFilter] = useState("")
  const [statusFilter, setStatusFilter] = useState<"" | "true" | "false">("")
  const [searchText, setSearchText] = useState("")
  const [q, setQ] = useState("")
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [editing, setEditing] = useState<any>(null)
  const [creating, setCreating] = useState(false)
  const [formType, setFormType] = useState("explore")
  const [formText, setFormText] = useState("")
  const [formMoodMin, setFormMoodMin] = useState("")
  const [formMoodMax, setFormMoodMax] = useState("")
  const [busy, setBusy] = useState(false)

  // Поиск с задержкой — не дёргаем API на каждый символ
  useEffect(() => {
    const t = setTimeout(() => setQ(searchText.trim()), 300)
    return () => clearTimeout(t)
  }, [searchText])

  const load = useCallback(() => {
    api.adminNarrativeTemplates(
      page, 50,
      typeFilter || undefined,
      sourceFilter || undefined,
      statusFilter === "" ? undefined : statusFilter === "true",
      q || undefined,
    ).then(setData).catch(() => {})
  }, [page, typeFilter, sourceFilter, statusFilter, q])

  const loadStats = useCallback(() => {
    api.adminNarrativeStats().then(setStats).catch(() => {})
  }, [])

  useEffect(() => { load() }, [load])
  useEffect(() => { loadStats() }, [loadStats])
  useEffect(() => { setSelected(new Set()) }, [page, typeFilter, sourceFilter, statusFilter, q])

  const startEdit = (t: any) => {
    setEditing(t)
    setFormType(t.template_type)
    setFormText(t.text_template)
    setFormMoodMin(t.mood_min == null ? "" : String(t.mood_min))
    setFormMoodMax(t.mood_max == null ? "" : String(t.mood_max))
    setCreating(false)
  }

  const startCreate = () => {
    setEditing(null)
    setFormType("explore")
    setFormText("")
    setFormMoodMin("")
    setFormMoodMax("")
    setCreating(true)
  }

  const cancelForm = () => {
    setEditing(null)
    setCreating(false)
    setFormText("")
    setFormMoodMin("")
    setFormMoodMax("")
  }

  const saveEdit = async () => {
    if (!editing) return
    try {
      await api.adminUpdateTemplate(editing.id, formText, formType, formMoodMin, formMoodMax)
      setEditing(null)
      load(); loadStats()
    } catch (e) { alert("Ошибка сохранения") }
  }

  const saveCreate = async () => {
    if (!formText.trim()) return
    try {
      await api.adminCreateTemplate(formType, formText, formMoodMin, formMoodMax)
      setCreating(false)
      setFormText("")
      setFormMoodMin("")
      setFormMoodMax("")
      load(); loadStats()
    } catch (e) { alert("Ошибка создания") }
  }

  const toggleSelect = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const bulk = async (action: "activate" | "deactivate" | "delete") => {
    if (selected.size === 0 || busy) return
    if (action === "delete" && !confirm(`Удалить выбранные шаблоны (${selected.size})?`)) return
    setBusy(true)
    try {
      await api.adminBulkTemplates([...selected], action)
      setSelected(new Set())
      load(); loadStats()
    } catch (e) { alert("Ошибка массовой операции") }
    setBusy(false)
  }

  const thinCount = stats ? stats.types.filter((t: any) => t.total < 5).length : 0
  const maxTotal = stats ? Math.max(...stats.types.map((t: any) => t.total), 1) : 1

  if (!data) return <div style={{ color: "var(--muted)", padding: 32 }}>Загрузка…</div>

  return (
    <div>
      {/* Create / Edit Form */}
      {(creating || editing) && (
        <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
          <div className="panel-header">
            {editing ? "Редактирование шаблона" : "Новый шаблон"}
            <button onClick={cancelForm} style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--border)", background: "var(--panel-bg)", cursor: "pointer" }}>Отмена</button>
          </div>
          <div className="panel-body">
            <div style={{ marginBottom: "var(--space-3)" }}>
              <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Тип</label>
              <select value={formType} onChange={(e) => setFormType(e.target.value)}
                style={{ padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)" }}>
                {TEMPLATE_TYPE_GROUPS.map((g) => (
                  <optgroup key={g.group} label={g.group}>
                    {g.types.map((t) => <option key={t.id} value={t.id}>{t.label} ({t.id})</option>)}
                  </optgroup>
                ))}
                <optgroup label="Legacy">
                  {FORM_TYPES.filter((t) => !TEMPLATE_TYPE_SET.has(t.id)).map((t) => <option key={t.id} value={t.id}>{t.label} ({t.id})</option>)}
                </optgroup>
              </select>
            </div>
            <div style={{ marginBottom: "var(--space-3)" }}>
              <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Текст шаблона</label>
              <textarea value={formText} onChange={(e) => setFormText(e.target.value)} rows={4}
                placeholder="Переменные: {hero_name}, {location_name}, {monster_name}, {terrain} (дат.), {discovery} (вин.), {landmark} (род.), {loot_text}, {destination} — полный словник на странице «Мастерская нарративов»"
                style={{ width: "100%", padding: "var(--space-2) var(--space-3)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)", fontFamily: "var(--font-body)", resize: "vertical" }} />
            </div>
            <div style={{ display: "flex", gap: "var(--space-2)", marginBottom: "var(--space-3)" }}>
              <div>
                <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Настроение от</label>
                <input type="number" min={0} max={100} step={1} value={formMoodMin}
                  onChange={(e) => setFormMoodMin(e.target.value)} placeholder="—"
                  style={{ width: 90, padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)" }} />
              </div>
              <div>
                <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Настроение до</label>
                <input type="number" min={0} max={100} step={1} value={formMoodMax}
                  onChange={(e) => setFormMoodMax(e.target.value)} placeholder="—"
                  style={{ width: 90, padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)" }} />
              </div>
              <div style={{ flex: 1, alignSelf: "flex-end", fontSize: 10, fontFamily: "var(--font-mono)", color: "var(--muted)", paddingBottom: 8 }}>
                пусто = без ограничения по настроению
              </div>
            </div>
            {formText.trim() && (
              <div style={{ marginBottom: "var(--space-3)", padding: "var(--space-2) var(--space-3)", border: "1px dashed var(--border)", borderRadius: "var(--radius-md)", background: "var(--bg)" }}>
                <div style={{ fontSize: 10, fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", marginBottom: 4 }}>Превью · примерные значения словника</div>
                <div style={{ fontSize: "var(--text-sm)", fontStyle: "italic", color: "var(--fg)" }}>{renderPreview(formText)}</div>
              </div>
            )}
            <div style={{ display: "flex", gap: "var(--space-2)" }}>
              <button onClick={editing ? saveEdit : saveCreate}
                style={{ padding: "6px 14px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: "pointer" }}>
                {editing ? "Сохранить" : "Создать"}
              </button>
              <button onClick={cancelForm}
                style={{ padding: "6px 14px", background: "var(--panel-bg)", color: "var(--fg)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "1px solid var(--border)", cursor: "pointer" }}>
                Отмена
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Coverage (покрытие типов) */}
      {stats && (
        <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
          <div className="panel-header">
            <span>Покрытие типов <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)", fontWeight: 400, textTransform: "none", letterSpacing: 0 }}>
              {stats.types.length} типов · активных {stats.active} из {stats.total}
            </span></span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)" }}>
              {stats.sources.map((s: any) => `${s.source}: ${s.count}`).join(" · ")}
            </span>
          </div>
          <div className="panel-body" style={{ maxHeight: 150, overflowY: "auto", display: "flex", flexWrap: "wrap", gap: "var(--space-2)" }}>
            {stats.types.map((t: any) => {
              const active = typeFilter === t.template_type
              const thin = t.total < 5
              const pct = Math.max(6, Math.round((t.total / maxTotal) * 100))
              return (
                <button key={t.template_type} type="button"
                  onClick={() => { setTypeFilter(active ? "" : t.template_type); setPage(1) }}
                  title={`${t.template_type}: ${t.active} активных из ${t.total}${thin ? " — мало шаблонов" : ""}`}
                  style={{ display: "flex", flexDirection: "column", gap: 3, padding: "4px 8px", borderRadius: "var(--radius-md)", minWidth: 100,
                    border: `1px solid ${active ? "var(--mp)" : thin ? "color-mix(in oklab, var(--warn), transparent 45%)" : "var(--border)"}`,
                    background: active ? "color-mix(in oklab, var(--mp), transparent 85%)" : "var(--panel-bg)",
                    cursor: "pointer", textAlign: "left" }}>
                  <span style={{ display: "flex", justifyContent: "space-between", gap: 6, fontSize: 11, fontFamily: "var(--font-mono)", color: "var(--fg)" }}>
                    <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: 120 }}>{t.template_type}</span>
                    <span style={{ color: thin ? "var(--warn)" : "var(--muted)" }}>{t.total}</span>
                  </span>
                  <span style={{ display: "block", height: 3, borderRadius: 2, background: "var(--border)", position: "relative", overflow: "hidden", width: "100%" }}>
                    <span style={{ position: "absolute", inset: 0, width: `${pct}%`, background: thin ? "var(--warn)" : "var(--success)" }} />
                  </span>
                </button>
              )
            })}
          </div>
          {thinCount > 0 && (
            <div style={{ padding: "var(--space-2) var(--space-3)", borderTop: "1px solid var(--border)", fontSize: 11, fontFamily: "var(--font-mono)", color: "var(--warn)" }}>
              ⚠ Тонкие типы (&lt;5 шаблонов): {thinCount} — клик по чипу фильтрует список
            </div>
          )}
        </div>
      )}

      {/* Templates List */}
      <div className="panel">
        <div className="panel-header">
          <span>Шаблоны нарративов <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)", fontWeight: 400, textTransform: "none", letterSpacing: 0 }}>{data.total} всего</span></span>
          <button onClick={startCreate}
            style={{ padding: "4px 12px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-sm)", fontSize: 11, border: "none", cursor: "pointer" }}>
            + Добавить
          </button>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", padding: "var(--space-2) var(--space-3)", borderBottom: "1px solid var(--border)", flexWrap: "wrap" }}>
          <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase" }}>Тип:</label>
          <select value={typeFilter} onChange={(e) => { setTypeFilter(e.target.value); setPage(1) }}
            style={{ padding: "4px 8px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", background: "var(--bg)", color: "var(--fg)", cursor: "pointer" }}>
            {FILTER_OPTIONS.map((f) => <option key={f.k} value={f.k}>{f.l}</option>)}
          </select>
          <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase" }}>Источник:</label>
          <select value={sourceFilter} onChange={(e) => { setSourceFilter(e.target.value); setPage(1) }}
            style={{ padding: "4px 8px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", background: "var(--bg)", color: "var(--fg)", cursor: "pointer" }}>
            <option value="">Все</option>
            {["system", "community", "llm", "manual"].map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
          <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase" }}>Статус:</label>
          <select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value as "" | "true" | "false"); setPage(1) }}
            style={{ padding: "4px 8px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", background: "var(--bg)", color: "var(--fg)", cursor: "pointer" }}>
            <option value="">Все</option>
            <option value="true">Активные</option>
            <option value="false">Ожидают</option>
          </select>
          <input value={searchText} onChange={(e) => setSearchText(e.target.value)}
            placeholder="Поиск по тексту…" aria-label="Поиск по тексту шаблона"
            style={{ flex: "1 1 160px", minWidth: 140, padding: "4px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", background: "var(--bg)", color: "var(--fg)", fontFamily: "var(--font-body)" }} />
        </div>
        {selected.size > 0 && (
          <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", padding: "var(--space-2) var(--space-3)", borderBottom: "1px solid var(--border)", background: "color-mix(in oklab, var(--mp), transparent 92%)", flexWrap: "wrap" }}>
            <span style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--fg)" }}>Выбрано: {selected.size}</span>
            <button type="button" disabled={busy} onClick={() => bulk("activate")}
              style={{ padding: "2px 10px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--success)", background: "transparent", color: "var(--success)", cursor: "pointer" }}>Активировать</button>
            <button type="button" disabled={busy} onClick={() => bulk("deactivate")}
              style={{ padding: "2px 10px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--warn)", background: "transparent", color: "var(--warn)", cursor: "pointer" }}>Снять</button>
            <button type="button" disabled={busy} onClick={() => bulk("delete")}
              style={{ padding: "2px 10px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--danger)", background: "transparent", color: "var(--danger)", cursor: "pointer" }}>Удалить</button>
            <button type="button" onClick={() => setSelected(new Set())}
              style={{ padding: "2px 10px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--border)", background: "var(--panel-bg)", color: "var(--fg)", cursor: "pointer" }}>Сброс</button>
          </div>
        )}
        <div className="panel-body" style={{ maxHeight: 400, overflowY: "auto" }}>
          {data.templates.map((t: any) => (
            <div key={t.id} style={{ padding: "var(--space-2) var(--space-3)", borderBottom: "1px solid var(--border)", display: "flex", alignItems: "center", gap: "var(--space-3)" }}>
              <input type="checkbox" checked={selected.has(t.id)} onChange={() => toggleSelect(t.id)}
                aria-label={`Выбрать шаблон ${t.id}`} style={{ cursor: "pointer", accentColor: "var(--mp)" }} />
              <span style={{ padding: "2px 6px", borderRadius: "var(--radius-pill)", fontSize: 10, fontFamily: "var(--font-mono)",
                background: t.is_active ? "color-mix(in oklab, var(--success), transparent 85%)" : "color-mix(in oklab, var(--warn), transparent 85%)",
                color: t.is_active ? "var(--success)" : "var(--warn)", whiteSpace: "nowrap" }}>
                {t.is_active ? "Активен" : "Ожидает"}
              </span>
              <span style={{ padding: "2px 6px", borderRadius: "var(--radius-pill)", fontSize: 10, fontFamily: "var(--font-mono)",
                background: "color-mix(in oklab, var(--fg), transparent 90%)", color: "var(--muted)", whiteSpace: "nowrap" }}>
                {t.source}
              </span>
              <span style={{ padding: "2px 6px", borderRadius: "var(--radius-pill)", fontSize: 10, fontFamily: "var(--font-mono)",
                background: "color-mix(in oklab, var(--mp), transparent 85%)", color: "var(--mp)", whiteSpace: "nowrap" }}>
                {t.template_type}
              </span>
              <span style={{ flex: 1, fontSize: "var(--text-sm)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{t.text_template}</span>
              <div style={{ display: "flex", gap: "var(--space-1)" }}>
                <button onClick={() => startEdit(t)} style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--mp)", background: "transparent", color: "var(--mp)", cursor: "pointer" }}>✎</button>
                {!t.is_active && <button onClick={() => api.adminApproveTemplate(t.id).then(load)} style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--success)", background: "transparent", color: "var(--success)", cursor: "pointer" }}>✓</button>}
                {t.is_active && <button onClick={() => api.adminRejectTemplate(t.id).then(load)} style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--warn)", background: "transparent", color: "var(--warn)", cursor: "pointer" }}>✕</button>}
                <button onClick={() => { if (confirm("Удалить?")) api.adminDeleteTemplate(t.id).then(load) }} style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--danger)", background: "transparent", color: "var(--danger)", cursor: "pointer" }}>🗑</button>
              </div>
            </div>
          ))}
        </div>
        <div style={{ padding: "var(--space-2) var(--space-3)", fontSize: 11, fontFamily: "var(--font-mono)", color: "var(--muted)", borderTop: "1px solid var(--border)" }}>
          Показано {data.templates.length} из {data.total}
        </div>
        {data.total > data.per_page && (
          <div style={{ display: "flex", justifyContent: "center", gap: "var(--space-2)", padding: "var(--space-3)" }}>
            <button onClick={() => setPage(Math.max(1, page - 1))} disabled={page === 1}
              style={{ padding: "4px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--border)", background: page === 1 ? "transparent" : "var(--panel-bg)", cursor: page === 1 ? "default" : "pointer" }}>Назад</button>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)", display: "flex", alignItems: "center" }}>{page}</span>
            <button onClick={() => setPage(page + 1)} disabled={data.templates.length < data.per_page}
              style={{ padding: "4px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--border)", background: data.templates.length < data.per_page ? "transparent" : "var(--panel-bg)", cursor: data.templates.length < data.per_page ? "default" : "pointer" }}>Вперёд</button>
          </div>
        )}
      </div>
    </div>
  )
}

/* ─── Simulation Panel ──────────────────────────────── */
function SimulationPanel() {
  const [result, setResult] = useState<any>(null)
  const [loading, setLoading] = useState(false)
  const [narrType, setNarrType] = useState("explore")
  const [narrLoc, setNarrLoc] = useState("")
  const [narrCount, setNarrCount] = useState(5)
  const [narrSentences, setNarrSentences] = useState(2)
  const [narrTone, setNarrTone] = useState("atmospheric")
  const [simTicks, setSimTicks] = useState(300)
  const [simResult, setSimResult] = useState<any>(null)
  const [simLoading, setSimLoading] = useState(false)
  const [locations, setLocations] = useState<{ id: string; name: string }[]>([])

  // Локации из БД — вместо захардкоженного списка
  useEffect(() => { api.getLocations().then(setLocations).catch(() => {}) }, [])

  // Full simulation (test user + hero + ticks → file)
  const runFullSimulation = async () => {
    setSimLoading(true)
    try {
      const res = await api.adminSimulationRun(simTicks)
      setSimResult(res)
    } catch (e: any) { setSimResult({ error: e.message }) }
    setSimLoading(false)
  }

  const genMonsters = async () => {
    setLoading(true)
    try { setResult(await api.adminGenerateMonsters(5)) } catch (e: any) { setResult({ error: e.message }) }
    setLoading(false)
  }

  const genItems = async () => {
    setLoading(true)
    try { setResult(await api.adminGenerateItems(10)) } catch (e: any) { setResult({ error: e.message }) }
    setLoading(false)
  }

  const genNarrativesModerated = async () => {
    setLoading(true)
    try {
      setResult(await api.adminGenerateNarrativesModerated(narrType, narrLoc, narrCount, narrSentences, narrTone))
    } catch (e: any) { setResult({ error: e.message }) }
    setLoading(false)
  }

  const genAll = async () => {
    setLoading(true)
    try { setResult(await api.adminGenerateAll()) } catch (e: any) { setResult({ error: e.message }) }
    setLoading(false)
  }

  const toneLabels: Record<string, string> = {
    atmospheric: "Атмосферный",
    comedy: "Комичный",
    epic: "Героический",
    grim: "Мрачный",
    calm: "Спокойный",
    mood: "По настроению",
    mysterious: "Загадочный",
    dramatic: "Драматичный",
  }

  return (
    <div>
      {/* Bulk generation */}
      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">Генерация всего сразу</div>
        <div className="panel-body">
          <p style={{ fontSize: "var(--text-sm)", color: "var(--muted)", marginBottom: "var(--space-3)" }}>
            Генерирует монстров, предметы и нарративы для всех локаций. Данные проходят автоматическую валидацию.
          </p>
          <button onClick={genAll} disabled={loading}
            style={{ padding: "8px 20px", background: "var(--epic)", color: "#fff", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", fontWeight: 600, border: "none", cursor: loading ? "wait" : "pointer", opacity: loading ? 0.5 : 1 }}>
            {loading ? "Генерация…" : "Сгенерировать всё"}
          </button>
        </div>
      </div>

      {/* Individual generation */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "var(--space-4)", marginBottom: "var(--space-4)" }}>
        <div className="panel">
          <div className="panel-header">Генерация монстров</div>
          <div className="panel-body">
            <p style={{ fontSize: "var(--text-sm)", color: "var(--muted)", marginBottom: "var(--space-3)" }}>5 монстров для случайных локаций.</p>
            <button onClick={genMonsters} disabled={loading}
              style={{ padding: "6px 14px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: loading ? "wait" : "pointer", opacity: loading ? 0.5 : 1 }}>
              {loading ? "..." : "Монстры"}
            </button>
          </div>
        </div>
        <div className="panel">
          <div className="panel-header">Генерация предметов</div>
          <div className="panel-body">
            <p style={{ fontSize: "var(--text-sm)", color: "var(--muted)", marginBottom: "var(--space-3)" }}>10 предметов через LLM.</p>
            <button onClick={genItems} disabled={loading}
              style={{ padding: "6px 14px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: loading ? "wait" : "pointer", opacity: loading ? 0.5 : 1 }}>
              {loading ? "..." : "Предметы"}
            </button>
          </div>
        </div>
      </div>

      {/* Narratives with moderation */}
      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">Генерация нарративов</div>
        <div className="panel-body">
          <div style={{ display: "flex", gap: "var(--space-3)", marginBottom: "var(--space-3)", flexWrap: "wrap" }}>
            <div>
              <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Тип</label>
              <select value={narrType} onChange={(e) => setNarrType(e.target.value)}
                style={{ padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)" }}>
                {["hero_victory","hero_defeat","enemy_ambush","spot_bandits","hear_wolves","leave_city","travel_road","travel_shortcut","cross_bridge","enter_city","bad_weather","discover_ruin","discover_cave","find_shrine","find_abandoned_cart","notice_tracks","hear_river","find_tracks","hear_birds","smell_flowers","sleep_in_inn","rest_by_fire","watch_sunset","meet_merchant","learn_rumors","hear_song","shelter_from_storm","find_loot","discover_treasure","remember_defeat","feel_confident","avoid_danger","search_danger","collect_herbs","generic_action","combat_start","combat_result","combat_defeat","explore","rest","loot","shop","social","travel","equip","death","thought","god_encourage","god_punish","god_heal","god_direct","god_quest","god_weather"].map((t) => <option key={t} value={t}>{t}</option>)}
              </select>
            </div>
            <div>
              <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Локация</label>
              <select value={narrLoc} onChange={(e) => setNarrLoc(e.target.value)}
                style={{ padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)" }}>
                <option value="">Универсальная</option>
                {locations.map((l) => <option key={l.id} value={l.name}>{l.name}</option>)}
              </select>
            </div>
            <div>
              <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Предложений</label>
              <select value={narrSentences} onChange={(e) => setNarrSentences(Number(e.target.value))}
                style={{ padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)" }}>
                {[1, 2, 3, 4, 5].map((n) => <option key={n} value={n}>{n}</option>)}
              </select>
            </div>
            <div>
              <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Тон</label>
              <select value={narrTone} onChange={(e) => setNarrTone(e.target.value)}
                style={{ padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)" }}>
                {Object.entries(toneLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </div>
            <div>
              <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Кол-во</label>
              <input type="number" value={narrCount} onChange={(e) => setNarrCount(Number(e.target.value))} min={1} max={20}
                style={{ padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", width: 60, background: "var(--bg)" }} />
            </div>
          </div>
          <div style={{ display: "flex", gap: "var(--space-2)" }}>
            <button onClick={genNarrativesModerated} disabled={loading}
              style={{ padding: "6px 14px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: loading ? "wait" : "pointer", opacity: loading ? 0.5 : 1 }}>
              {loading ? "Генерация…" : "Сгенерировать с валидацией"}
            </button>
          </div>
        </div>
      </div>

      {/* Hero Simulation */}
      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">Симуляция героя (тест)</div>
        <div className="panel-body">
          <p style={{ fontSize: "var(--text-sm)", color: "var(--muted)", marginBottom: "var(--space-3)" }}>
            Создаёт тестового пользователя и героя, запускает N тиков, сохраняет отчёт в файл.
          </p>
          <div style={{ display: "flex", gap: "var(--space-3)", alignItems: "end" }}>
            <div>
              <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Тиков</label>
              <input type="number" value={simTicks} onChange={(e) => setSimTicks(Number(e.target.value))} min={10} max={500}
                style={{ padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", width: 80, background: "var(--bg)" }} />
            </div>
            <button onClick={runFullSimulation} disabled={simLoading}
              style={{ padding: "8px 20px", background: "var(--epic)", color: "#fff", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: simLoading ? "wait" : "pointer", opacity: simLoading ? 0.5 : 1, fontWeight: 600 }}>
              {simLoading ? "Симуляция…" : "Запустить симуляцию"}
            </button>
          </div>
        </div>
      </div>

      {simResult && (
        <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
          <div className="panel-header">
            Результат симуляции ({simResult.ticks || 0} тиков)
            {simResult.report_file && (
              <span style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", marginLeft: 8 }}>
                Файл: {simResult.report_file}
              </span>
            )}
          </div>
          <div className="panel-body">
            {simResult.error ? (
              <div style={{ color: "var(--danger)" }}>{simResult.error}</div>
            ) : (
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "var(--space-4)" }}>
                {/* State Distribution */}
                <div>
                  <h4 style={{ fontFamily: "var(--font-heading)", fontSize: "var(--text-sm)", fontWeight: 600, marginBottom: "var(--space-2)" }}>Распределение состояний</h4>
                  {simResult.state_distribution && Object.entries(simResult.state_distribution).map(([state, pct]) => (
                    <div key={state} style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 4 }}>
                      <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)", minWidth: 100 }}>{state}</span>
                      <div style={{ flex: 1, height: 16, background: "var(--bg-elevated)", borderRadius: 4, overflow: "hidden" }}>
                        <div style={{ height: "100%", width: `${pct}%`, background: "var(--accent)", borderRadius: 4, transition: "width 0.3s" }} />
                      </div>
                      <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)", minWidth: 40 }}>{String(pct)}%</span>
                    </div>
                  ))}
                </div>
                {/* Stats */}
                <div>
                  <h4 style={{ fontFamily: "var(--font-heading)", fontSize: "var(--text-sm)", fontWeight: 600, marginBottom: "var(--space-2)" }}>Статистика</h4>
                  <div style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-sm)", lineHeight: 2 }}>
                    <div>Боёв: <span style={{ color: "var(--accent)" }}>{simResult.combat_stats?.total || 0}</span></div>
                    <div>Среднее HP: <span style={{ color: "var(--accent)" }}>{simResult.avg_hp || 0}</span></div>
                    <div>Среднее настроение: <span style={{ color: "var(--accent)" }}>{simResult.avg_mood || 0}</span></div>
                    <div>Золото заработано: <span style={{ color: "var(--success)" }}>{simResult.gold_earned || 0}</span></div>
                    <div>Квестов взято: <span style={{ color: "var(--accent)" }}>{simResult.quests_taken || 0}</span></div>
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {result && (
        <div className="panel">
          <div className="panel-header">Результат</div>
          <div className="panel-body" style={{ maxHeight: 300, overflowY: "auto" }}>
            {result.error ? (
              <div style={{ color: "var(--danger)" }}>{result.error}</div>
            ) : (
              <pre style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", whiteSpace: "pre-wrap", wordBreak: "break-all" }}>{JSON.stringify(result, null, 2)}</pre>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

/* ─── P-0: Предложения игроков ─────────────────────── */
function SuggestionsPanel() {
  const [items, setItems] = useState<any[]>([])
  const [status, setStatus] = useState("pending")
  const [msg, setMsg] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const data = await api.adminSuggestions(status || undefined)
      setItems(data.suggestions || [])
    } catch {}
    setLoading(false)
  }, [status])

  useEffect(() => { load() }, [load])

  const approve = async (s: any) => {
    const type = prompt(
      "Тип события для шаблона (например explore, socialize, fishing).\nТекст предложения станет активным community-шаблоном этого типа. Оставь пустым — только статус «одобрено».",
      "explore",
    )
    if (type === null) return
    try {
      const res = await api.adminApproveSuggestion(s.id, type.trim() || undefined)
      setMsg(res.template_id ? `Одобрено → шаблон «${res.template_type}» в ротации` : "Одобрено (без шаблона)")
    } catch (e: any) {
      setMsg(e?.message || "Ошибка одобрения")
    }
    load()
  }

  const reject = async (s: any) => {
    const comment = prompt("Причина отказа (необязательно):", "")
    if (comment === null) return
    try {
      await api.adminRejectSuggestion(s.id, comment)
      setMsg("Отклонено")
    } catch (e: any) {
      setMsg(e?.message || "Ошибка отказа")
    }
    load()
  }

  return (
    <div>
      <div className="panel">
        <div className="panel-header">
          <span>Предложения игроков <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)" }}>{items.length}</span></span>
          <select value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Фильтр статуса предложений"
            style={{ padding: "4px 8px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", background: "var(--bg)", color: "var(--fg)", cursor: "pointer" }}>
            <option value="pending">Ожидают</option>
            <option value="approved">Одобрены</option>
            <option value="rejected">Отклонены</option>
            <option value="">Все</option>
          </select>
        </div>
        <div className="panel-body" style={{ display: "grid", gap: "var(--space-2)" }}>
          {msg && <div role="status" style={{ fontSize: "var(--text-sm)", color: "var(--muted)" }}>{msg}</div>}
          {loading && <div style={{ color: "var(--muted)" }}>Загрузка…</div>}
          {!loading && items.length === 0 && (
            <div style={{ color: "var(--muted)", fontSize: "var(--text-sm)" }}>Пока тихо — предложений нет.</div>
          )}
          {items.map((s) => (
            <div key={s.id} style={{ background: "var(--bg-elevated)", borderRadius: "var(--radius-md)", padding: "10px 12px" }}>
              <div style={{ display: "flex", alignItems: "baseline", gap: 8, flexWrap: "wrap" }}>
                <b style={{ fontSize: "var(--text-sm)" }}>{s.title}</b>
                <span style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)" }}>
                  {s.suggestion_type} · {s.status} · {String(s.created_at).slice(0, 16).replace("T", " ")}
                </span>
              </div>
              <div style={{ marginTop: 6, fontSize: "var(--text-sm)", color: "var(--fg)", whiteSpace: "pre-wrap" }}>{s.content}</div>
              {s.admin_comment && (
                <div style={{ marginTop: 4, fontSize: "var(--text-xs)", color: "var(--muted)" }}>Комментарий: {s.admin_comment}</div>
              )}
              {s.status === "pending" && (
                <div style={{ marginTop: 8, display: "flex", gap: 6 }}>
                  <button onClick={() => approve(s)} aria-label={`Одобрить предложение ${s.title}`}
                    style={{ padding: "4px 12px", background: "color-mix(in oklab, var(--success), transparent 75%)", color: "var(--success)", border: "1px solid var(--success)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", cursor: "pointer" }}>
                    ✓ Одобрить
                  </button>
                  <button onClick={() => reject(s)} aria-label={`Отклонить предложение ${s.title}`}
                    style={{ padding: "4px 12px", background: "color-mix(in oklab, var(--danger), transparent 80%)", color: "var(--danger)", border: "1px solid var(--danger)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", cursor: "pointer" }}>
                    ✗ Отклонить
                  </button>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

/* ─── Moderation Panel ─────────────────────────────── */
function ModerationPanel() {
  const [templates, setTemplates] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [typeFilter, setTypeFilter] = useState("")
  const [editing, setEditing] = useState<any>(null)
  const [editText, setEditText] = useState("")
  const [loading, setLoading] = useState(false)
  const [genMsg, setGenMsg] = useState("")

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const data = await api.adminNarrativeTemplates(page, 50, typeFilter || undefined, undefined, false)
      setTemplates(data.templates || [])
      setTotal(data.total || 0)
    } catch (e) {}
    setLoading(false)
  }, [page, typeFilter])

  useEffect(() => { load() }, [load])

  const approve = async (id: string) => {
    await api.adminApproveTemplate(id)
    load()
  }

  const reject = async (id: string) => {
    await api.adminRejectTemplate(id)
    load()
  }

  const deleteTemplate = async (id: string) => {
    if (confirm("Удалить шаблон?")) {
      await api.adminDeleteTemplate(id)
      load()
    }
  }

  const saveEdit = async () => {
    if (!editing) return
    await api.adminUpdateTemplate(editing.id, editText, editing.template_type)
    setEditing(null)
    setEditText("")
    load()
  }

  return (
    <div>
      <div className="panel">
        <div className="panel-header">
          <span>Модерация нарративов <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)" }}>{total} всего</span></span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", padding: "var(--space-2) var(--space-3)", borderBottom: "1px solid var(--border)" }}>
          <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase" }}>Тип:</label>
          <select value={typeFilter} onChange={(e) => { setTypeFilter(e.target.value); setPage(1) }}
            style={{ padding: "4px 8px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", background: "var(--bg)", color: "var(--fg)", cursor: "pointer" }}>
            {FILTER_OPTIONS.map((f) => <option key={f.k} value={f.k}>{f.l}</option>)}
          </select>
          {total > 0 && (
            <button aria-label="Одобрить все отобранные шаблоны"
              onClick={async () => {
                const scope = typeFilter ? `тип «${typeFilter}»` : "ВСЕ ожидающие шаблоны"
                if (!confirm(`Одобрить ${total} шаблонов (${scope})? Одобренные сразу попадут в ротацию.`)) return
                try {
                  const res = await api.adminApproveBatch(typeFilter ? { template_type: typeFilter } : { all: "true" })
                  setGenMsg(res.message || `Одобрено: ${res.approved}, осталось: ${res.remaining}`)
                } catch (e: any) {
                  setGenMsg(e?.message || "Ошибка одобрения")
                }
                load()
              }}
              style={{ padding: "4px 10px", background: "color-mix(in oklab, var(--success), transparent 75%)", color: "var(--success)", border: "1px solid var(--success)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", cursor: "pointer" }}>
              Одобрить всё отобранное ({total})
            </button>
          )}
          {genMsg && <span role="status" style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>{genMsg}</span>}
        </div>
        <div className="panel-body" style={{ maxHeight: 400, overflowY: "auto" }}>
          {loading && <div style={{ color: "var(--muted)", padding: 16 }}>Загрузка…</div>}
          {!loading && templates.length === 0 && <div style={{ color: "var(--muted)", padding: 16 }}>Нет шаблонов для отображения</div>}
          {templates.map((t: any) => (
            <div key={t.id} style={{ padding: "var(--space-2) var(--space-3)", borderBottom: "1px solid var(--border)", display: "flex", alignItems: "center", gap: "var(--space-3)" }}>
              <span style={{ padding: "2px 6px", borderRadius: "var(--radius-pill)", fontSize: 10, fontFamily: "var(--font-mono)",
                background: t.is_active ? "color-mix(in oklab, var(--success), transparent 85%)" : "color-mix(in oklab, var(--warn), transparent 85%)",
                color: t.is_active ? "var(--success)" : "var(--warn)", whiteSpace: "nowrap" }}>
                {t.is_active ? "Одобрен" : "Ожидает"}
              </span>
              <span style={{ padding: "2px 6px", borderRadius: "var(--radius-pill)", fontSize: 10, fontFamily: "var(--font-mono)",
                background: "color-mix(in oklab, var(--fg), transparent 90%)", color: "var(--muted)", whiteSpace: "nowrap" }}>
                {t.source}
              </span>
              <span style={{ padding: "2px 6px", borderRadius: "var(--radius-pill)", fontSize: 10, fontFamily: "var(--font-mono)",
                background: "color-mix(in oklab, var(--mp), transparent 85%)", color: "var(--mp)", whiteSpace: "nowrap" }}>
                {t.template_type}
              </span>
              <span style={{ flex: 1, fontSize: "var(--text-sm)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{t.text_template}</span>
              <div style={{ display: "flex", gap: "var(--space-1)" }}>
                <button onClick={() => { setEditing(t); setEditText(t.text_template) }} style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--mp)", background: "transparent", color: "var(--mp)", cursor: "pointer" }}>✎</button>
                {!t.is_active && <button onClick={() => approve(t.id)} style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--success)", background: "transparent", color: "var(--success)", cursor: "pointer" }}>✓</button>}
                {t.is_active && <button onClick={() => reject(t.id)} style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--warn)", background: "transparent", color: "var(--warn)", cursor: "pointer" }}>✕</button>}
                <button onClick={() => deleteTemplate(t.id)} style={{ padding: "2px 8px", borderRadius: "var(--radius-sm)", fontSize: 11, border: "1px solid var(--danger)", background: "transparent", color: "var(--danger)", cursor: "pointer" }}>🗑</button>
              </div>
            </div>
          ))}
        </div>
        {total > 50 && (
          <div style={{ display: "flex", justifyContent: "center", gap: "var(--space-2)", padding: "var(--space-3)" }}>
            <button onClick={() => setPage(Math.max(1, page - 1))} disabled={page === 1}
              style={{ padding: "4px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--border)", background: page === 1 ? "transparent" : "var(--panel-bg)", cursor: page === 1 ? "default" : "pointer" }}>Назад</button>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)", display: "flex", alignItems: "center" }}>{page}</span>
            <button onClick={() => setPage(page + 1)} disabled={templates.length < 50}
              style={{ padding: "4px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--border)", background: templates.length < 50 ? "transparent" : "var(--panel-bg)", cursor: templates.length < 50 ? "default" : "pointer" }}>Вперёд</button>
          </div>
        )}
      </div>

      {/* Edit Form */}
      {editing && (
        <div className="panel" style={{ marginTop: "var(--space-4)" }}>
          <div className="panel-header">Редактирование шаблона</div>
          <div className="panel-body">
            <div style={{ marginBottom: "var(--space-3)" }}>
              <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Текст шаблона</label>
              <textarea value={editText} onChange={(e) => setEditText(e.target.value)} rows={4}
                style={{ width: "100%", padding: "var(--space-2) var(--space-3)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)", fontFamily: "var(--font-body)", resize: "vertical" }} />
            </div>
            <div style={{ display: "flex", gap: "var(--space-2)" }}>
              <button onClick={saveEdit}
                style={{ padding: "6px 14px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: "pointer" }}>
                Сохранить
              </button>
              <button onClick={() => { setEditing(null); setEditText("") }}
                style={{ padding: "6px 14px", background: "var(--panel-bg)", color: "var(--fg)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "1px solid var(--border)", cursor: "pointer" }}>
                Отмена
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

/* ─── Tests Panel ───────────────────────────────────── */
function TestsPanel() {
  const [results, setResults] = useState<any>(null)
  const [running, setRunning] = useState(false)

  const runTests = async () => {
    setRunning(true)
    try { setResults(await api.adminRunTests()) } catch (e: any) { setResults({ error: e.message }) }
    setRunning(false)
  }

  useEffect(() => { api.adminLastTests().then(setResults).catch(() => {}) }, [])

  return (
    <div>
      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">Тесты проекта</div>
        <div className="panel-body">
          <button onClick={runTests} disabled={running}
            style={{ padding: "8px 20px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", fontWeight: 600, border: "none", cursor: running ? "wait" : "pointer", opacity: running ? 0.5 : 1 }}>
            {running ? "Запуск тестов…" : "Запустить тесты"}
          </button>
        </div>
      </div>
      {results && (
        <div className="panel">
          <div className="panel-header">
            Результаты
            {results.run_at && <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)", fontWeight: 400, textTransform: "none", letterSpacing: 0 }}>{formatDate(results.run_at)}</span>}
          </div>
          <div className="panel-body">
            {results.error ? (
              <div style={{ color: "var(--danger)" }}>{results.error}</div>
            ) : (
              <>
                <div style={{ display: "flex", gap: "var(--space-4)", marginBottom: "var(--space-3)" }}>
                  <div style={{ textAlign: "center" }}>
                    <div style={{ fontFamily: "var(--font-mono)", fontWeight: 700, fontSize: "var(--text-2xl)", color: "var(--success)" }}>{results.passed}</div>
                    <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>Пройдено</div>
                  </div>
                  <div style={{ textAlign: "center" }}>
                    <div style={{ fontFamily: "var(--font-mono)", fontWeight: 700, fontSize: "var(--text-2xl)", color: results.failed > 0 ? "var(--danger)" : "var(--muted)" }}>{results.failed}</div>
                    <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>Провалено</div>
                  </div>
                  <div style={{ textAlign: "center" }}>
                    <div style={{ fontFamily: "var(--font-mono)", fontWeight: 700, fontSize: "var(--text-2xl)", color: results.errors > 0 ? "var(--warn)" : "var(--muted)" }}>{results.errors}</div>
                    <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>Ошибки</div>
                  </div>
                </div>
                {results.output && (
                  <pre style={{ fontFamily: "var(--font-mono)", fontSize: 11, background: "var(--panel-bg)", padding: "var(--space-3)", borderRadius: "var(--radius-md)", maxHeight: 300, overflowY: "auto", whiteSpace: "pre-wrap" }}>{results.output}</pre>
                )}
              </>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

/* ─── Config Panel ──────────────────────────────────── */
function ConfigPanel() {
  const [configs, setConfigs] = useState<any[]>([])
  const [expanded, setExpanded] = useState<string | null>(null)
  const [llmEnabled, setLlmEnabled] = useState(false)
  const [llmLoading, setLlmLoading] = useState(false)
  const [llmTone, setLlmTone] = useState("standard")
  const [llmSentences, setLlmSentences] = useState(2)

  useEffect(() => {
    api.adminConfigs().then((d) => setConfigs(d.configs)).catch(() => {})
    api.adminLlmStatus().then((d) => {
      setLlmEnabled(d.auto_generate || false)
      setLlmTone(d.tone || "standard")
      setLlmSentences(d.sentences || 2)
    }).catch(() => {})
  }, [])

  const toggleLlm = async () => {
    setLlmLoading(true)
    try {
      const result = await api.adminLlmToggle(!llmEnabled)
      setLlmEnabled(result.auto_generate)
    } catch (e) {}
    setLlmLoading(false)
  }

  const updateLlmConfig = async (key: string, value: any) => {
    setLlmLoading(true)
    try {
      await api.adminUpdateConfig("narrative_generation", { ...{ auto_generate: llmEnabled, tone: llmTone, sentences: llmSentences }, [key]: value })
      if (key === "tone") setLlmTone(value)
      if (key === "sentences") setLlmSentences(value)
    } catch (e) {}
    setLlmLoading(false)
  }

  const toneLabels: Record<string, string> = {
    standard: "Стандартный (RPG)",
    comic: "Комичный (Godville)",
    dark: "Тёмное фэнтези",
  }

  return (
    <div>
      {/* LLM Toggle */}
      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">LLM Генерация нарративов</div>
        <div className="panel-body">
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "var(--space-3)" }}>
            <div>
              <div style={{ fontWeight: 500, fontSize: "var(--text-sm)" }}>Автогенерация через LLM</div>
              <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>Для онлайн-пользователей. Медленно, но заполняет базу данных.</div>
            </div>
            <button onClick={toggleLlm} disabled={llmLoading}
              style={{ padding: "8px 16px", borderRadius: "var(--radius-pill)", border: "none", cursor: llmLoading ? "wait" : "pointer", fontWeight: 600, fontSize: "var(--text-sm)",
                background: llmEnabled ? "var(--success)" : "var(--fg)", color: llmEnabled ? "#fff" : "var(--accent-on)", opacity: llmLoading ? 0.5 : 1 }}>
              {llmEnabled ? "Включено" : "Выключено"}
            </button>
          </div>
          <div style={{ display: "flex", gap: "var(--space-4)", flexWrap: "wrap" }}>
            <div>
              <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Стиль</label>
              <select value={llmTone} onChange={(e) => updateLlmConfig("tone", e.target.value)}
                style={{ padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)" }}>
                {Object.entries(toneLabels).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </div>
            <div>
              <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Предложений</label>
              <select value={llmSentences} onChange={(e) => updateLlmConfig("sentences", Number(e.target.value))}
                style={{ padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)" }}>
                {[1, 2, 3, 4].map((n) => <option key={n} value={n}>{n}</option>)}
              </select>
            </div>
          </div>
        </div>
      </div>

      {/* All Configs */}
      <div className="panel">
        <div className="panel-header">Игровая конфигурация</div>
        <div className="panel-body" style={{ maxHeight: 500, overflowY: "auto" }}>
          {configs.map((c) => (
            <div key={c.key} style={{ borderBottom: "1px solid var(--border)", padding: "var(--space-2) 0" }}>
              <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", cursor: "pointer" }} onClick={() => setExpanded(expanded === c.key ? null : c.key)}>
                <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-sm)", fontWeight: 600 }}>{c.key}</span>
                <span style={{ flex: 1, fontSize: "var(--text-xs)", color: "var(--muted)" }}>{c.description}</span>
                <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>{expanded === c.key ? "▲" : "▼"}</span>
              </div>
              {expanded === c.key && (
                <pre style={{ fontFamily: "var(--font-mono)", fontSize: 11, background: "var(--panel-bg)", padding: "var(--space-3)", borderRadius: "var(--radius-md)", marginTop: "var(--space-2)", maxHeight: 200, overflowY: "auto", whiteSpace: "pre-wrap" }}>
                  {JSON.stringify(c.value, null, 2)}
                </pre>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

/* ─── Backup Panel ──────────────────────────────────── */
function BackupPanel() {
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<any>(null)
  const [importData, setImportData] = useState("")

  const exportData = async () => {
    setLoading(true)
    try {
      const data = await api.adminExport()
      // Download as file
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" })
      const url = URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `tes_idle_backup_${new Date().toISOString().slice(0, 10)}.json`
      a.click()
      URL.revokeObjectURL(url)
      setResult({ message: "Экспорт завершён", stats: {
        locations: data.locations?.length || 0,
        monsters: data.monsters?.length || 0,
        items: data.items?.length || 0,
        templates: data.narrative_templates?.length || 0,
        configs: data.game_configs?.length || 0,
      }})
    } catch (e: any) { setResult({ error: e.message }) }
    setLoading(false)
  }

  const exportToFile = async () => {
    setLoading(true)
    try { setResult(await api.adminExportFile()) } catch (e: any) { setResult({ error: e.message }) }
    setLoading(false)
  }

  const importJson = async () => {
    if (!importData.trim()) return
    setLoading(true)
    try {
      const data = JSON.parse(importData)
      setResult(await api.adminImport(data))
    } catch (e: any) { setResult({ error: e.message }) }
    setLoading(false)
  }

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = (ev) => {
      const text = ev.target?.result as string
      setImportData(text)
    }
    reader.readAsText(file)
  }

  return (
    <div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "var(--space-4)", marginBottom: "var(--space-4)" }}>
        {/* Export */}
        <div className="panel">
          <div className="panel-header">Экспорт данных</div>
          <div className="panel-body">
            <p style={{ fontSize: "var(--text-sm)", color: "var(--muted)", marginBottom: "var(--space-3)" }}>
              Скачать все игровые данные в JSON файл для бэкапа.
            </p>
            <div style={{ display: "flex", gap: "var(--space-2)" }}>
              <button onClick={exportData} disabled={loading}
                style={{ padding: "6px 14px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: loading ? "wait" : "pointer", opacity: loading ? 0.5 : 1 }}>
                {loading ? "..." : "Скачать JSON"}
              </button>
              <button onClick={exportToFile} disabled={loading}
                style={{ padding: "6px 14px", background: "var(--panel-bg)", color: "var(--fg)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "1px solid var(--border)", cursor: loading ? "wait" : "pointer", opacity: loading ? 0.5 : 1 }}>
                {loading ? "..." : "Сохранить на сервер"}
              </button>
            </div>
          </div>
        </div>

        {/* Import */}
        <div className="panel">
          <div className="panel-header">Импорт данных</div>
          <div className="panel-body">
            <p style={{ fontSize: "var(--text-sm)", color: "var(--muted)", marginBottom: "var(--space-3)" }}>
              Загрузить данные из JSON бэкапа. Дубликаты пропускаются.
            </p>
            <input type="file" accept=".json" onChange={handleFileUpload}
              style={{ marginBottom: "var(--space-2)", fontSize: "var(--text-sm)" }} />
            <button onClick={importJson} disabled={loading || !importData.trim()}
              style={{ padding: "6px 14px", background: "var(--success)", color: "#fff", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: loading || !importData.trim() ? "default" : "pointer", opacity: loading || !importData.trim() ? 0.5 : 1 }}>
              {loading ? "Импорт…" : "Импортировать"}
            </button>
          </div>
        </div>
      </div>

      {result && (
        <div className="panel">
          <div className="panel-header">Результат</div>
          <div className="panel-body">
            {result.error ? (
              <div style={{ color: "var(--danger)" }}>{result.error}</div>
            ) : (
              <pre style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", whiteSpace: "pre-wrap" }}>{JSON.stringify(result, null, 2)}</pre>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

/* ─── Main Admin Page ───────────────────────────────── */
export function AdminPage() {
  const [activeTab, setActiveTab] = useState("overview")

  return (
    <div className="anim-fade-up">
      <div style={{ marginBottom: "var(--space-4)" }}>
        <h1 style={{ fontFamily: "var(--font-display)", fontSize: "var(--text-2xl)", fontWeight: 800, letterSpacing: "-0.02em", marginBottom: "var(--space-2)" }}>Админ-панель</h1>
        <p style={{ color: "var(--muted)", fontSize: "var(--text-sm)" }}>Управление игрой, пользователями и контентом</p>
      </div>

      <div className="tabs" style={{ marginBottom: "var(--space-4)" }}>
        {tabs.map((t) => (
          <button key={t.key} className={`tab ${activeTab === t.key ? "active" : ""}`} onClick={() => setActiveTab(t.key)}>{t.label}</button>
        ))}
      </div>

      {activeTab === "overview" && <OverviewPanel />}
      {activeTab === "users" && <UsersPanel />}
      {activeTab === "heroes" && <HeroesPanel />}
      {activeTab === "narratives" && <NarrativesPanel />}
      {activeTab === "narrative-analytics" && <NarrativeAnalyticsPanel />}
      {activeTab === "moderation" && <ModerationPanel />}
      {activeTab === "suggestions" && <SuggestionsPanel />}
      {activeTab === "simulation" && <SimulationPanel />}
      {activeTab === "tests" && <TestsPanel />}
      {activeTab === "config" && <ConfigPanel />}
      {activeTab === "backup" && <BackupPanel />}
    </div>
  )
}

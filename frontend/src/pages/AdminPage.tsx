import { useState, useEffect, useCallback, useRef } from "react"
import { api, type DecisionAuditReport, type DecisionAuditRecentEvent } from "@/lib/api"
import { formatNumber, formatDate } from "@/lib/utils"
import { VAR_GROUPS, TEMPLATE_TYPES, TEMPLATE_TYPE_GROUPS } from "@/components/narrativeData"
import "./admin-observatory.css"

/* ─── Narrative helpers (Библиотека) ────────────────── */
// Превью шаблона: подстановка примеров из словника; неизвестные переменные остаются видимыми
function renderPreview(text: string): string {
  const samples: Record<string, string> = {}
  for (const g of VAR_GROUPS) for (const v of g.vars) samples[v.var.replace(/[{}]/g, "")] = v.example
  return text.replace(/\{(\w+)\}/g, (match, key: string) => samples[key] ?? match)
}

/* ─── Tab system ────────────────────────────────────── */
const tabs = [
  { key: "overview", label: "Обзор", section: "Пульс мира", mark: "◈" },
  { key: "users", label: "Пользователи", section: "Население", mark: "◌" },
  { key: "heroes", label: "Герои", section: "Население", mark: "⚔" },
  { key: "decision-audit", label: "Аудит решений", section: "Население", mark: "◉" },
  { key: "narratives", label: "Нарративы", section: "Летопись", mark: "✦" },
  { key: "narrative-analytics", label: "Аналитика нарративов", section: "Летопись", mark: "⌁" },
  { key: "moderation", label: "Модерация", section: "Летопись", mark: "✓" },
  { key: "suggestions", label: "Предложения", section: "Летопись", mark: "✉" },
  { key: "items", label: "Предметы", section: "Скарб", mark: "⚗" },
  { key: "monsters", label: "Монстры", section: "Скарб", mark: "☠" },
  { key: "simulation", label: "Симуляция", section: "Операции", mark: "◇" },
  { key: "tests", label: "Тесты", section: "Операции", mark: "⌘" },
  { key: "config", label: "Конфиг", section: "Устав", mark: "≡" },
  { key: "backup", label: "Бэкап", section: "Устав", mark: "↧", destructive: true },
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

/* ─── Narrative batch import ─────────────────────────── */
type NarrativeBatchPolicy = "pending" | "active_system"

type NarrativeBatchRow = {
  index: number
  valid: boolean
  errors?: string[]
  warnings?: string[]
  preview?: string | null
  normalized?: {
    template_type?: string
    text_template?: string
    source?: string
    variables?: string[]
    mood_min?: number | null
    mood_max?: number | null
    is_active?: boolean
  } | null
  variables?: string[]
}

type NarrativeBatchResult = {
  valid: boolean
  errors?: string[]
  rows?: NarrativeBatchRow[]
  summary?: { total: number; valid: number; invalid: number }
}

function NarrativeBatchPanel({ onImported }: { onImported: () => void }) {
  const [batchText, setBatchText] = useState("")
  const [policy, setPolicy] = useState<NarrativeBatchPolicy>("pending")
  const [validation, setValidation] = useState<{ key: string; result: NarrativeBatchResult } | null>(null)
  const [message, setMessage] = useState<{ kind: "success" | "error"; text: string } | null>(null)
  const [busy, setBusy] = useState<"validate" | "import" | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const key = `${policy}\u0000${batchText}`
  const result = validation?.key === key ? validation.result : null
  const canImport = result?.valid === true && busy === null

  const readTemplates = (): Array<Record<string, unknown>> | null => {
    try {
      const parsed: unknown = JSON.parse(batchText)
      if (Array.isArray(parsed)) return parsed as Array<Record<string, unknown>>
      if (parsed && typeof parsed === "object" && Array.isArray((parsed as { templates?: unknown }).templates)) {
        return (parsed as { templates: Array<Record<string, unknown>> }).templates
      }
      throw new Error("JSON должен быть массивом шаблонов или объектом с полем templates.")
    } catch (error: any) {
      setValidation({ key, result: { valid: false, errors: [error.message || "Неверный JSON."], rows: [], summary: { total: 0, valid: 0, invalid: 0 } } })
      return null
    }
  }

  const validate = async () => {
    const templates = readTemplates()
    if (!templates) return
    setBusy("validate")
    setMessage(null)
    try {
      const next = await api.adminValidateNarrativeBatch({ templates, activation_policy: policy })
      setValidation({ key, result: next })
    } catch (error: any) {
      setValidation({ key, result: { valid: false, errors: [error.message || "Не удалось проверить пакет."], rows: [], summary: { total: 0, valid: 0, invalid: 0 } } })
    } finally {
      setBusy(null)
    }
  }

  const importBatch = async () => {
    if (!canImport) return
    const templates = readTemplates()
    if (!templates) return
    setBusy("import")
    setMessage(null)
    try {
      const imported = await api.adminImportNarrativeBatch({ templates, activation_policy: policy })
      setMessage({ kind: "success", text: `Импортировано шаблонов: ${imported.imported}.` })
      setValidation(null)
      onImported()
    } catch (error: any) {
      setMessage({ kind: "error", text: error.message || "Импорт не выполнен: пакет не изменён." })
    } finally {
      setBusy(null)
    }
  }

  return (
    <section className="narrative-batch panel" aria-labelledby="narrative-batch-title">
      <div className="panel-header">
        <span id="narrative-batch-title">Импорт JSON-пакета</span>
        <span className="narrative-batch-atomic">атомарно · до 200 строк</span>
      </div>
      <div className="panel-body narrative-batch-body">
        <p className="narrative-batch-help">Вставьте JSON-массив или целый объект пакета с полем <code>templates</code>; можно выбрать файл <code>.json</code>. Сначала проверьте пакет: импорт станет доступен только для этой неизменённой версии и выбранной политики.</p>
        <div className="narrative-batch-policy" role="group" aria-label="Политика активации">
          <span className="narrative-batch-label">После импорта</span>
          <label>
            <input type="radio" name="batch-policy" value="pending" checked={policy === "pending"} onChange={() => setPolicy("pending")} />
            <span><b>Ожидают модерации</b><small>Любой источник; шаблоны не активируются.</small></span>
          </label>
          <label>
            <input type="radio" name="batch-policy" value="active_system" checked={policy === "active_system"} onChange={() => setPolicy("active_system")} />
            <span><b>Сразу активировать system</b><small>Только строки с <code>"source": "system"</code>.</small></span>
          </label>
        </div>
        <div className="narrative-batch-file-row">
          <label className="narrative-batch-label" htmlFor="narrative-batch-json">JSON-пакет шаблонов</label>
          <input
            ref={fileInputRef}
            className="narrative-batch-file"
            type="file"
            accept="application/json,.json"
            aria-label="Загрузить JSON-файл с шаблонами"
            onChange={async (event) => {
              const file = event.currentTarget.files?.[0]
              if (!file) return
              try {
                const text = await file.text()
                JSON.parse(text)
                setBatchText(text)
                setValidation(null)
                setMessage({ kind: "success", text: `Файл «${file.name}» загружен. Проверьте пакет перед импортом.` })
              } catch {
                setMessage({ kind: "error", text: "Файл не содержит корректный JSON." })
              } finally {
                event.currentTarget.value = ""
              }
            }}
          />
          <button type="button" onClick={() => fileInputRef.current?.click()}>Выбрать файл…</button>
        </div>
        <textarea
          id="narrative-batch-json"
          className="narrative-batch-json"
          value={batchText}
          onChange={(event) => { setBatchText(event.target.value); setMessage(null) }}
          rows={10}
          spellCheck={false}
          placeholder={'[\n  {\n    "template_type": "explore",\n    "text_template": "{hero_name} идёт по {terrain}.",\n    "source": "community"\n  }\n]'}
          aria-describedby="narrative-batch-help"
        />
        <div className="narrative-batch-actions">
          <button type="button" onClick={validate} disabled={busy !== null}>{busy === "validate" ? "Проверяем…" : "Проверить пакет"}</button>
          <button type="button" className="narrative-batch-import" onClick={importBatch} disabled={!canImport}>{busy === "import" ? "Импортируем…" : "Импортировать"}</button>
          {result && !result.valid && <span className="narrative-batch-stale">Исправьте ошибки и проверьте пакет заново.</span>}
        </div>

        <div id="narrative-batch-help" className="narrative-batch-results" aria-live="polite" aria-atomic="false">
          {message && <p className={`narrative-batch-message ${message.kind}`} role="status">{message.text}</p>}
          {result && (
            <>
              <div className={`narrative-batch-summary ${result.valid ? "is-valid" : "is-invalid"}`}>
                <strong>{result.valid ? "Пакет готов к импорту" : "Пакет требует исправлений"}</strong>
                {result.summary && <span>Всего: {result.summary.total} · корректных: {result.summary.valid} · с ошибками: {result.summary.invalid}</span>}
              </div>
              {result.errors && result.errors.length > 0 && (
                <ul className="narrative-batch-errors" aria-label="Ошибки пакета">{result.errors.map((error, index) => <li key={`${error}-${index}`}>{error}</li>)}</ul>
              )}
              {result.rows && result.rows.length > 0 && (
                <ol className="narrative-batch-rows" aria-label="Результаты проверки строк">
                  {result.rows.map((row) => (
                    <li key={row.index} className={`narrative-batch-row ${row.valid ? "is-valid" : "is-invalid"}`}>
                      <div className="narrative-batch-row-title"><strong>Строка {row.index + 1}</strong><span>{row.valid ? "Корректна" : "Ошибка"}</span></div>
                      {row.preview != null && <p><b>Превью:</b> {row.preview}</p>}
                      {row.variables && <p><b>Переменные:</b> {row.variables.length ? row.variables.map((variable) => <code key={variable}>{`{${variable}}`}</code>) : "нет"}</p>}
                      {row.normalized && <p className="narrative-batch-normalized"><b>Будет сохранено:</b> <code>{row.normalized.template_type}</code> · {row.normalized.source} · {row.normalized.is_active ? "активен" : "ожидает"}</p>}
                      {row.errors && row.errors.length > 0 && <ul className="narrative-batch-errors">{row.errors.map((error, index) => <li key={`${error}-${index}`}>{error}</li>)}</ul>}
                      {row.warnings && row.warnings.length > 0 && <ul className="narrative-batch-warnings">{row.warnings.map((warning, index) => <li key={`${warning}-${index}`}>{warning}</li>)}</ul>}
                    </li>
                  ))}
                </ol>
              )}
            </>
          )}
        </div>
      </div>
    </section>
  )
}

/* ─── Decision Audit Panel ───────────────────────────── */
const AUDIT_EVENT_LABELS: Record<DecisionAuditRecentEvent["event_type"], string> = {
  intent_selected: "намерение выбрано",
  intent_held: "намерение удержано",
  intent_switched: "намерение сменено",
  action_started: "действие начато",
  action_completed: "действие завершено",
  action_failed: "действие не удалось",
}

function DecisionAuditPanel() {
  const [data, setData] = useState<DecisionAuditReport | null>(null)
  const [days, setDays] = useState(30)
  const [limit, setLimit] = useState(50)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  const load = useCallback(() => {
    setLoading(true)
    setError("")
    api.adminBrainStats(days, limit)
      .then(setData)
      .catch(() => setError("Не удалось загрузить аудит решений"))
      .finally(() => setLoading(false))
  }, [days, limit])

  useEffect(() => { load() }, [load])

  if (loading && !data) return <div style={{ color: "var(--muted)", padding: 32 }}>Загрузка аудита…</div>
  if (error && !data) return <div style={{ color: "var(--danger)", padding: 32 }}>{error}</div>
  if (!data) return null

  const intentTotal = data.intent_by_goal.reduce((total, goal) => total + goal.selected + goal.held + goal.switched, 0)
  const actionTotal = data.action_outcomes.reduce((total, action) => total + action.completed + action.failed, 0)
  const failedActions = data.action_outcomes.reduce((total, action) => total + action.failed, 0)
  const topGoal = data.intent_by_goal[0]
  const concentration = topGoal && intentTotal > 0 ? ((topGoal.selected + topGoal.held + topGoal.switched) / intentTotal) * 100 : 0
  const topHeroEvents = data.heroes[0]?.events ?? 0
  const heroEvents = data.heroes.reduce((total, hero) => total + hero.events, 0)

  return (
    <section className="decision-audit" aria-labelledby="decision-audit-title">
      <div className="decision-audit-heading">
        <div>
          <p className="decision-audit-kicker">Brain telemetry · append-only</p>
          <h3 id="decision-audit-title">Аудит решений</h3>
          <p>Проверка перекоса мозга: какая цель забирает решения, как часто намерение меняется и чем заканчиваются действия.</p>
        </div>
        <div className="decision-audit-controls">
          <label>Период
            <select value={days} onChange={(event) => setDays(Number(event.target.value))}>
              <option value={7}>7 дней</option>
              <option value={30}>30 дней</option>
              <option value={90}>90 дней</option>
              <option value={365}>365 дней</option>
            </select>
          </label>
          <label>Событий
            <select value={limit} onChange={(event) => setLimit(Number(event.target.value))}>
              <option value={25}>25</option>
              <option value={50}>50</option>
              <option value={100}>100</option>
              <option value={200}>200</option>
            </select>
          </label>
          <button type="button" onClick={load} disabled={loading}>{loading ? "Обновление…" : "Обновить"}</button>
        </div>
      </div>

      <div className="decision-audit-summary">
        <div className="decision-audit-signal">
          <span>Концентрация цели</span>
          <strong>{concentration.toFixed(1)}%</strong>
          <small>{topGoal ? `${topGoal.goal ?? "без цели"} · ${topGoal.selected + topGoal.held + topGoal.switched} из ${intentTotal}` : "Пока нет намерений"}</small>
          {concentration >= 60 && <em>Проверьте перекос</em>}
        </div>
        <div className="decision-audit-stat"><span>Решений</span><strong>{formatNumber(intentTotal)}</strong><small>выбрано / удержано / сменено</small></div>
        <div className="decision-audit-stat"><span>Действий</span><strong>{formatNumber(actionTotal)}</strong><small>{failedActions ? `${failedActions} не завершились` : "без сбоев"}</small></div>
        <div className="decision-audit-stat"><span>Героев в аудите</span><strong>{formatNumber(data.heroes.length)}</strong><small>{heroEvents ? `лидер: ${topHeroEvents}/${heroEvents} событий` : "событий пока нет"}</small></div>
      </div>

      <div className="decision-audit-grid">
        <div className="panel decision-audit-panel">
          <div className="panel-header">Распределение целей <span>выбрано · удержано · сменено</span></div>
          <div className="panel-body">
            {data.intent_by_goal.length === 0 ? <p className="decision-audit-empty">За выбранный период намерений нет.</p> : data.intent_by_goal.map((goal) => {
              const count = goal.selected + goal.held + goal.switched
              const percentage = intentTotal ? (count / intentTotal) * 100 : 0
              return <div className="decision-goal-row" key={goal.goal ?? "none"}>
                <div className="decision-goal-label"><b>{goal.goal ?? "без цели"}</b><span>{percentage.toFixed(1)}% · {count}</span></div>
                <div className="decision-goal-track" aria-label={`${goal.goal ?? "без цели"}: ${percentage.toFixed(1)}%`}><i style={{ width: `${percentage}%` }} /></div>
                <div className="decision-event-counts"><span>В {goal.selected}</span><span>У {goal.held}</span><span>С {goal.switched}</span><span>U {goal.avg_utility.toFixed(2)}</span></div>
              </div>
            })}
          </div>
        </div>

        <div className="panel decision-audit-panel">
          <div className="panel-header">Исходы действий <span>завершено · не удалось</span></div>
          <div className="panel-body">
            {data.action_outcomes.length === 0 ? <p className="decision-audit-empty">Исходов действий пока нет.</p> : data.action_outcomes.map((action) => {
              const count = action.completed + action.failed
              const failureRate = count ? (action.failed / count) * 100 : 0
              return <div className="decision-action-row" key={`${action.goal}-${action.action}`}>
                <div><b>{action.action ?? "без действия"}</b><span>{action.goal ?? "без цели"}</span></div>
                <div className="decision-outcome-bar"><i style={{ width: `${100 - failureRate}%` }} /><i style={{ width: `${failureRate}%` }} /></div>
                <small><strong>{action.completed}</strong> готово · <strong>{action.failed}</strong> сбой</small>
              </div>
            })}
          </div>
        </div>
      </div>

      <div className="panel decision-audit-panel">
        <div className="panel-header">Концентрация по героям <span>все телеметрические события периода</span></div>
        <div className="panel-body" style={{ padding: 0 }}>
          {data.heroes.length === 0 ? <p className="decision-audit-empty">Герои ещё не оставили след в аудите.</p> : <table className="decision-audit-table"><thead><tr><th>Герой</th><th>События</th><th>Намерения</th><th>Действия</th><th>Доля</th></tr></thead><tbody>{data.heroes.map((hero) => {
            const share = heroEvents ? (hero.events / heroEvents) * 100 : 0
            return <tr key={hero.hero}><td><b>{hero.hero}</b><small>ур. {hero.level}</small></td><td>{hero.events}</td><td>В {hero.selected} · У {hero.held} · С {hero.switched}</td><td>✓ {hero.completed} · ! {hero.failed}</td><td>{share.toFixed(1)}%</td></tr>
          })}</tbody></table>}
        </div>
      </div>

      <div className="panel decision-audit-panel">
        <div className="panel-header">Последние события <span>за {data.range.days} дн. · последние {data.limit}</span></div>
        <div className="panel-body" style={{ padding: 0 }}>
          {data.recent_events.length === 0 ? <p className="decision-audit-empty">За выбранный период событий нет.</p> : <table className="decision-audit-table"><thead><tr><th>Когда</th><th>Герой</th><th>Событие</th><th>Цель / действие</th><th>Контекст</th></tr></thead><tbody>{data.recent_events.map((event, index) => <tr key={`${event.created_at}-${event.hero}-${index}`}><td>{formatDate(event.created_at)}</td><td>{event.hero}</td><td><span className={`decision-event-type ${event.event_type}`}>{AUDIT_EVENT_LABELS[event.event_type]}</span></td><td><b>{event.goal ?? "—"}</b>{event.action && <small>{event.action}</small>}</td><td>день {event.game_day ?? "—"} · час {event.game_hour ?? "—"}{event.utility != null && ` · U ${event.utility.toFixed(2)}`}</td></tr>)}</tbody></table>}
        </div>
        <div className="decision-audit-note">API сейчас отдаёт период и лимит последних событий. Причины и metadata сохраняются аудитом, но в ответ маршрута ещё не включены; фильтрация по ним и постраничный offset появятся после расширения API.</div>
      </div>
    </section>
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

  if (!data) return <div style={{ color: "var(--muted)", padding: 32 }}>Загрузка…</div>

  return (
    <div>
      <NarrativeBatchPanel onImported={() => { load(); loadStats() }} />

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
            <span>Покрытие типов
              <span className="narrative-coverage-summary">
                {stats.types.length} типов · активных {stats.active} из {stats.total} · цель 60 на тип ·{" "}
                <b className={thinCount ? "is-pending" : ""}>{thinCount} не дотягивают</b>
              </span>
            </span>
            <span className="narrative-coverage-sources">
              {stats.sources.map((s: any) => `${s.source}: ${s.count}`).join(" · ")}
            </span>
          </div>
          <div className="panel-body narrative-coverage-grid">
            {stats.types.map((t: any) => {
              const active = typeFilter === t.template_type
              const pct = Math.min(100, Math.round((t.total / 60) * 100))
              const missing = Math.max(0, 60 - t.total)
              const pending = t.total - t.active
              return (
                <button key={t.template_type} type="button"
                  className={`narrative-coverage-tile ${active ? "active" : ""} ${missing ? "is-thin" : "is-ready"}`}
                  onClick={() => { setTypeFilter(active ? "" : t.template_type); setPage(1) }}
                  title={`${t.template_type}: всего ${t.total}, активных ${t.active}, ожидают ${pending}${missing ? `, не хватает ${missing} до 60` : " — цель достигнута"}`}
                  aria-pressed={active}>
                  <span className="narrative-coverage-name">{t.template_type}</span>
                  <span className="narrative-coverage-count"><strong>{t.total}</strong><small>/60</small></span>
                  <span className="narrative-coverage-meta">
                    <span className="is-active">активно<b>{t.active}</b></span>
                    <span className={pending ? "is-pending" : ""}>ожидает<b>{pending}</b></span>
                  </span>
                  <span className="narrative-coverage-track" aria-hidden="true"><i style={{ width: `${pct}%` }} /></span>
                  <span className="narrative-coverage-missing">{missing ? `−${missing} до цели` : "цель достигнута"}</span>
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
/* ─── Каталог: предметы ─────────────────────────────── */
const RARITY_RU: Record<string, string> = {
  common: "Обычный", uncommon: "Необычный", rare: "Редкий", epic: "Эпический", legendary: "Легендарный",
}
const ITEM_TYPE_RU: Record<string, string> = {
  consumable: "Расходник", equipment: "Экипировка", junk: "Хлам",
}
const SLOT_RU: Record<string, string> = {
  weapon: "Оружие", head: "Голова", body: "Тело", legs: "Ноги", ring: "Кольцо", amulet: "Амулет",
}

const emptyItemForm = {
  name: "", description: "", item_type: "consumable", rarity: "common", icon: "🍎",
  weight: "0.5", sell_price: "5", is_active: true, tags: "",
  heal_hp: "0", reduce_hunger: "0", reduce_fatigue: "0", boost_morale: "0",
  buff_attack: "0", buff_duration_ticks: "0", soul_restore: "0",
  equip_slot: "weapon", attack_bonus: "0", defense_bonus: "0", hp_bonus: "0", speed_bonus: "0",
}

const fieldStyle: React.CSSProperties = {
  width: "100%", padding: "8px 10px", background: "var(--bg)", color: "var(--fg)",
  border: "1px solid var(--border)", borderRadius: "var(--radius-sm)", fontSize: 13,
}
const labelStyle: React.CSSProperties = {
  display: "block", marginBottom: 4, color: "var(--muted)",
  font: "600 11px/1.3 'Fira Code', monospace", letterSpacing: ".05em", textTransform: "uppercase",
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <label style={{ display: "block" }}><span style={labelStyle}>{label}</span>{children}</label>
}

function ItemsPanel() {
  const [rows, setRows] = useState<any[]>([])
  const [counts, setCounts] = useState<Record<string, number>>({})
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [typeFilter, setTypeFilter] = useState("")
  const [search, setSearch] = useState("")
  const [q, setQ] = useState("")
  const [loading, setLoading] = useState(false)
  const [notice, setNotice] = useState<{ kind: "ok" | "err"; text: string } | null>(null)
  const [form, setForm] = useState({ ...emptyItemForm })
  const [editingId, setEditingId] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const perPage = 40

  useEffect(() => {
    const t = setTimeout(() => { setQ(search); setPage(1) }, 300)
    return () => clearTimeout(t)
  }, [search])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const res = await api.adminItems(page, typeFilter || undefined, q || undefined)
      setRows(res.items)
      setCounts(res.counts ?? {})
      setTotal(res.total)
    } catch (e: any) { setNotice({ kind: "err", text: e.message }) }
    setLoading(false)
  }, [page, typeFilter, q])

  useEffect(() => { load() }, [load])

  const reset = () => { setForm({ ...emptyItemForm }); setEditingId(null); setShowForm(false) }

  const submit = async () => {
    if (!form.name.trim()) { setNotice({ kind: "err", text: "Имя обязательно" }); return }
    try {
      const payload = { ...form, name: form.name.trim() }
      if (editingId) await api.adminUpdateItem(editingId, payload)
      else await api.adminCreateItem(payload)
      setNotice({ kind: "ok", text: editingId ? "Предмет обновлён" : `Предмет «${form.name}» создан` })
      reset(); load()
    } catch (e: any) { setNotice({ kind: "err", text: e.message }) }
  }

  const startEdit = (row: any) => {
    setEditingId(row.id); setShowForm(true)
    setForm({
      ...emptyItemForm,
      ...Object.fromEntries(Object.entries(row).map(([k, v]) => [k, v === null || v === undefined ? "" : String(v)])),
      tags: Array.isArray(row.tags) ? row.tags.join(", ") : "",
      is_active: row.is_active,
    } as any)
  }

  const remove = async (row: any) => {
    if (!window.confirm(`Удалить «${row.name}»? Если предмет у кого-то в инвентаре — он будет выключен, а не удалён.`)) return
    try {
      const res = await api.adminDeleteItem(row.id)
      setNotice({ kind: "ok", text: res.status === "deleted" ? "Предмет удалён" : "Предмет выключен (используется в игре)" })
      load()
    } catch (e: any) { setNotice({ kind: "err", text: e.message }) }
  }

  const isEquip = form.item_type === "equipment"
  const isConsumable = form.item_type === "consumable"

  return (
    <div>
      {notice && (
        <div role="status" style={{
          padding: "10px 14px", marginBottom: "var(--space-3)", borderRadius: "var(--radius-md)", fontSize: 13,
          border: `1px solid ${notice.kind === "ok" ? "var(--success)" : "var(--danger)"}`,
          color: notice.kind === "ok" ? "var(--success)" : "var(--danger)",
        }}>{notice.text}</div>
      )}

      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">
          <span>Каталог предметов <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--muted)", textTransform: "none", letterSpacing: 0, fontWeight: 400 }}>
            {total} всего · расходники {counts.consumable ?? 0} · экипировка {counts.equipment ?? 0} · хлам {counts.junk ?? 0}
          </span></span>
          <button onClick={() => { reset(); setShowForm(!showForm) }}
            style={{ padding: "6px 14px", background: "var(--accent)", color: "var(--accent-on)", border: "none", borderRadius: "var(--radius-md)", fontSize: 13, fontWeight: 600 }}>
            {showForm ? "Свернуть" : "+ Новый предмет"}
          </button>
        </div>

        {showForm && (
          <div className="panel-body" style={{ borderBottom: "1px solid var(--border)" }}>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--space-3)", marginBottom: "var(--space-3)" }}>
              <Field label="Имя"><input style={fieldStyle} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Зелье лечения" /></Field>
              <Field label="Тип">
                <select style={fieldStyle} value={form.item_type} onChange={(e) => setForm({ ...form, item_type: e.target.value })}>
                  <option value="consumable">Расходник</option>
                  <option value="equipment">Экипировка</option>
                  <option value="junk">Хлам</option>
                </select>
              </Field>
              <Field label="Редкость">
                <select style={fieldStyle} value={form.rarity} onChange={(e) => setForm({ ...form, rarity: e.target.value })}>
                  {Object.entries(RARITY_RU).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                </select>
              </Field>
              <Field label="Иконка"><input style={fieldStyle} value={form.icon} onChange={(e) => setForm({ ...form, icon: e.target.value })} maxLength={4} /></Field>
              <Field label="Вес"><input style={fieldStyle} value={form.weight} onChange={(e) => setForm({ ...form, weight: e.target.value })} inputMode="decimal" /></Field>
              <Field label="Цена продажи 🪙"><input style={fieldStyle} value={form.sell_price} onChange={(e) => setForm({ ...form, sell_price: e.target.value })} inputMode="numeric" /></Field>
            </div>

            <Field label="Описание">
              <textarea style={{ ...fieldStyle, minHeight: 60, resize: "vertical" }} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
            </Field>

            <div style={{ marginTop: "var(--space-3)" }}>
              <Field label="Теги (через запятую: fish, herb, lockpick, stolen)">
                <input style={fieldStyle} value={form.tags} onChange={(e) => setForm({ ...form, tags: e.target.value })} placeholder="herb, component" />
              </Field>
            </div>

            {isConsumable && (
              <>
                <p style={{ margin: "var(--space-4) 0 var(--space-2)", color: "var(--accent)", font: "600 11px/1.3 'Fira Code', monospace", letterSpacing: ".08em", textTransform: "uppercase" }}>Эффекты расходника</p>
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))", gap: "var(--space-3)" }}>
                  <Field label="+HP"><input style={fieldStyle} value={form.heal_hp} onChange={(e) => setForm({ ...form, heal_hp: e.target.value })} inputMode="numeric" /></Field>
                  <Field label="−Голод"><input style={fieldStyle} value={form.reduce_hunger} onChange={(e) => setForm({ ...form, reduce_hunger: e.target.value })} inputMode="decimal" /></Field>
                  <Field label="−Усталость"><input style={fieldStyle} value={form.reduce_fatigue} onChange={(e) => setForm({ ...form, reduce_fatigue: e.target.value })} inputMode="decimal" /></Field>
                  <Field label="+Боевой дух"><input style={fieldStyle} value={form.boost_morale} onChange={(e) => setForm({ ...form, boost_morale: e.target.value })} inputMode="decimal" /></Field>
                  <Field label="+Атака (баф)"><input style={fieldStyle} value={form.buff_attack} onChange={(e) => setForm({ ...form, buff_attack: e.target.value })} inputMode="numeric" /></Field>
                  <Field label="Тиков бафа"><input style={fieldStyle} value={form.buff_duration_ticks} onChange={(e) => setForm({ ...form, buff_duration_ticks: e.target.value })} inputMode="numeric" /></Field>
                  <Field label="Восст. души"><input style={fieldStyle} value={form.soul_restore} onChange={(e) => setForm({ ...form, soul_restore: e.target.value })} inputMode="decimal" /></Field>
                </div>
              </>
            )}

            {isEquip && (
              <>
                <p style={{ margin: "var(--space-4) 0 var(--space-2)", color: "var(--accent)", font: "600 11px/1.3 'Fira Code', monospace", letterSpacing: ".08em", textTransform: "uppercase" }}>Статы экипировки</p>
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))", gap: "var(--space-3)" }}>
                  <Field label="Слот">
                    <select style={fieldStyle} value={form.equip_slot} onChange={(e) => setForm({ ...form, equip_slot: e.target.value })}>
                      {Object.entries(SLOT_RU).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                    </select>
                  </Field>
                  <Field label="+Атака"><input style={fieldStyle} value={form.attack_bonus} onChange={(e) => setForm({ ...form, attack_bonus: e.target.value })} inputMode="numeric" /></Field>
                  <Field label="+Защита"><input style={fieldStyle} value={form.defense_bonus} onChange={(e) => setForm({ ...form, defense_bonus: e.target.value })} inputMode="numeric" /></Field>
                  <Field label="+HP"><input style={fieldStyle} value={form.hp_bonus} onChange={(e) => setForm({ ...form, hp_bonus: e.target.value })} inputMode="numeric" /></Field>
                  <Field label="+Скорость"><input style={fieldStyle} value={form.speed_bonus} onChange={(e) => setForm({ ...form, speed_bonus: e.target.value })} inputMode="decimal" /></Field>
                </div>
              </>
            )}

            <div style={{ display: "flex", alignItems: "center", gap: "var(--space-3)", marginTop: "var(--space-4)" }}>
              <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 13 }}>
                <input type="checkbox" checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />
                Активен (доступен в игре)
              </label>
              <div style={{ marginLeft: "auto", display: "flex", gap: "var(--space-2)" }}>
                <button onClick={reset} style={{ padding: "8px 16px", background: "var(--panel-bg)", color: "var(--fg)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: 13 }}>Отмена</button>
                <button onClick={submit} style={{ padding: "8px 20px", background: "var(--accent)", color: "var(--accent-on)", border: "none", borderRadius: "var(--radius-md)", fontSize: 13, fontWeight: 600 }}>
                  {editingId ? "Сохранить" : "Создать"}
                </button>
              </div>
            </div>
          </div>
        )}

        <div className="panel-body" style={{ display: "flex", gap: "var(--space-2)", flexWrap: "wrap", alignItems: "center" }}>
          <input style={{ ...fieldStyle, maxWidth: 240 }} value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Поиск по имени…" />
          <select style={{ ...fieldStyle, maxWidth: 190 }} value={typeFilter} onChange={(e) => { setTypeFilter(e.target.value); setPage(1) }}>
            <option value="">Все типы</option>
            {Object.entries(ITEM_TYPE_RU).map(([k, l]) => <option key={k} value={k}>{l} ({counts[k] ?? 0})</option>)}
          </select>
          <button onClick={load} disabled={loading} style={{ padding: "8px 14px", background: "var(--panel-bg)", color: "var(--fg)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: 13 }}>
            {loading ? "…" : "Обновить"}
          </button>
        </div>
      </div>

      <div className="panel">
        <div className="panel-header">Список <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--muted)", fontWeight: 400, textTransform: "none", letterSpacing: 0 }}>страница {page} из {Math.max(1, Math.ceil(total / perPage))}</span></div>
        <div className="panel-body" style={{ padding: 0, overflowX: "auto" }}>
          <table className="decision-audit-table">
            <thead>
              <tr>
                <th style={{ textAlign: "left" }}>Предмет</th>
                <th style={{ textAlign: "left" }}>Тип</th>
                <th style={{ textAlign: "left" }}>Статы</th>
                <th style={{ textAlign: "right" }}>Вес</th>
                <th style={{ textAlign: "right" }}>Цена</th>
                <th style={{ textAlign: "right" }}>Действия</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id}>
                  <td>
                    <strong>{row.icon} {row.name}</strong>
                    <small style={{ color: "var(--muted)" }}>{RARITY_RU[row.rarity] ?? row.rarity}{row.tags?.length ? ` · ${row.tags.join(", ")}` : ""}{!row.is_active ? " · выключен" : ""}</small>
                  </td>
                  <td><span className="decision-event-type">{ITEM_TYPE_RU[row.item_type] ?? row.item_type}</span></td>
                  <td style={{ fontFamily: "var(--font-mono)", fontSize: 12 }}>
                    {row.item_type === "equipment"
                      ? `${SLOT_RU[row.equip_slot] ?? row.equip_slot ?? "—"} · ⚔${row.attack_bonus} 🛡${row.defense_bonus} ❤${row.hp_bonus}`
                      : row.item_type === "consumable"
                        ? `❤+${row.heal_hp} 🍗−${row.reduce_hunger} 😊+${row.boost_morale}`
                        : "—"}
                  </td>
                  <td style={{ textAlign: "right", fontFamily: "var(--font-mono)", fontSize: 12 }}>{row.weight}</td>
                  <td style={{ textAlign: "right", fontFamily: "var(--font-mono)", fontSize: 12 }}>{row.sell_price}🪙</td>
                  <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
                    <button onClick={() => startEdit(row)} style={{ padding: "4px 10px", marginRight: 6, background: "var(--panel-bg)", color: "var(--fg)", border: "1px solid var(--border)", borderRadius: "var(--radius-sm)", fontSize: 12 }}>Правка</button>
                    <button onClick={() => remove(row)} style={{ padding: "4px 10px", background: "transparent", color: "var(--danger)", border: "1px solid var(--danger)", borderRadius: "var(--radius-sm)", fontSize: 12 }}>Удалить</button>
                  </td>
                </tr>
              ))}
              {rows.length === 0 && (
                <tr><td colSpan={6} style={{ textAlign: "center", color: "var(--muted)", padding: "var(--space-5)" }}>{loading ? "Загрузка…" : "Ничего не найдено"}</td></tr>
              )}
            </tbody>
          </table>
        </div>
        {total > perPage && (
          <div style={{ display: "flex", gap: "var(--space-2)", justifyContent: "center", padding: "var(--space-3)", borderTop: "1px solid var(--border)" }}>
            <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1} style={{ padding: "6px 14px", background: "var(--panel-bg)", color: "var(--fg)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: 13 }}>← Назад</button>
            <button onClick={() => setPage((p) => p + 1)} disabled={page >= Math.ceil(total / perPage)} style={{ padding: "6px 14px", background: "var(--panel-bg)", color: "var(--fg)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: 13 }}>Вперёд →</button>
          </div>
        )}
      </div>
    </div>
  )
}

/* ─── Каталог: монстры ──────────────────────────────── */
const emptyMonsterForm = {
  name: "", description: "", min_level: "1", max_level: "5", hp: "50",
  attack_min: "5", attack_max: "10", defense: "0", xp_reward: "20",
  gold_min: "5", gold_max: "15", is_active: true, location_id: "",
}

function MonstersPanel() {
  const [rows, setRows] = useState<any[]>([])
  const [locations, setLocations] = useState<Array<{ id: string; name: string }>>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [locFilter, setLocFilter] = useState("")
  const [loading, setLoading] = useState(false)
  const [notice, setNotice] = useState<{ kind: "ok" | "err"; text: string } | null>(null)
  const [form, setForm] = useState({ ...emptyMonsterForm })
  const [editingId, setEditingId] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const perPage = 40

  useEffect(() => { api.adminContentOptions().then((o) => setLocations(o.locations)).catch(() => {}) }, [])

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const res = await api.adminMonsters(page, locFilter || undefined)
      setRows(res.monsters); setTotal(res.total)
    } catch (e: any) { setNotice({ kind: "err", text: e.message }) }
    setLoading(false)
  }, [page, locFilter])

  useEffect(() => { load() }, [load])

  const reset = () => { setForm({ ...emptyMonsterForm }); setEditingId(null); setShowForm(false) }

  const submit = async () => {
    if (!form.name.trim()) { setNotice({ kind: "err", text: "Имя обязательно" }); return }
    try {
      const payload = { ...form, name: form.name.trim() }
      if (editingId) await api.adminUpdateMonster(editingId, payload)
      else await api.adminCreateMonster(payload)
      setNotice({ kind: "ok", text: editingId ? "Монстр обновлён" : `Монстр «${form.name}» создан` })
      reset(); load()
    } catch (e: any) { setNotice({ kind: "err", text: e.message }) }
  }

  const startEdit = (row: any) => {
    setEditingId(row.id); setShowForm(true)
    setForm({
      name: row.name ?? "", description: row.description ?? "",
      min_level: String(row.min_level), max_level: String(row.max_level), hp: String(row.hp),
      attack_min: String(row.attack_min), attack_max: String(row.attack_max), defense: String(row.defense),
      xp_reward: String(row.xp_reward), gold_min: String(row.gold_min), gold_max: String(row.gold_max),
      is_active: row.is_active, location_id: row.location_id ?? "",
    })
  }

  const remove = async (row: any) => {
    if (!window.confirm(`Удалить монстра «${row.name}»?`)) return
    try {
      await api.adminDeleteMonster(row.id)
      setNotice({ kind: "ok", text: "Монстр удалён" }); load()
    } catch (e: any) { setNotice({ kind: "err", text: e.message }) }
  }

  return (
    <div>
      {notice && (
        <div role="status" style={{
          padding: "10px 14px", marginBottom: "var(--space-3)", borderRadius: "var(--radius-md)", fontSize: 13,
          border: `1px solid ${notice.kind === "ok" ? "var(--success)" : "var(--danger)"}`,
          color: notice.kind === "ok" ? "var(--success)" : "var(--danger)",
        }}>{notice.text}</div>
      )}

      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">
          <span>Бестиарий <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--muted)", textTransform: "none", letterSpacing: 0, fontWeight: 400 }}>
            {total} монстров в базе
          </span></span>
          <button onClick={() => { reset(); setShowForm(!showForm) }}
            style={{ padding: "6px 14px", background: "var(--accent)", color: "var(--accent-on)", border: "none", borderRadius: "var(--radius-md)", fontSize: 13, fontWeight: 600 }}>
            {showForm ? "Свернуть" : "+ Новый монстр"}
          </button>
        </div>

        {showForm && (
          <div className="panel-body" style={{ borderBottom: "1px solid var(--border)" }}>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))", gap: "var(--space-3)", marginBottom: "var(--space-3)" }}>
              <Field label="Имя"><input style={fieldStyle} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Драугр-воин" /></Field>
              <Field label="Локация">
                <select style={fieldStyle} value={form.location_id} onChange={(e) => setForm({ ...form, location_id: e.target.value })}>
                  <option value="">— без локации —</option>
                  {locations.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
                </select>
              </Field>
              <Field label="Мин. уровень"><input style={fieldStyle} value={form.min_level} onChange={(e) => setForm({ ...form, min_level: e.target.value })} inputMode="numeric" /></Field>
              <Field label="Макс. уровень"><input style={fieldStyle} value={form.max_level} onChange={(e) => setForm({ ...form, max_level: e.target.value })} inputMode="numeric" /></Field>
            </div>

            <Field label="Описание">
              <textarea style={{ ...fieldStyle, minHeight: 60, resize: "vertical" }} value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} />
            </Field>

            <p style={{ margin: "var(--space-4) 0 var(--space-2)", color: "var(--accent)", font: "600 11px/1.3 'Fira Code', monospace", letterSpacing: ".08em", textTransform: "uppercase" }}>Боевые характеристики</p>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))", gap: "var(--space-3)" }}>
              <Field label="HP"><input style={fieldStyle} value={form.hp} onChange={(e) => setForm({ ...form, hp: e.target.value })} inputMode="numeric" /></Field>
              <Field label="Атака мин."><input style={fieldStyle} value={form.attack_min} onChange={(e) => setForm({ ...form, attack_min: e.target.value })} inputMode="numeric" /></Field>
              <Field label="Атака макс."><input style={fieldStyle} value={form.attack_max} onChange={(e) => setForm({ ...form, attack_max: e.target.value })} inputMode="numeric" /></Field>
              <Field label="Защита"><input style={fieldStyle} value={form.defense} onChange={(e) => setForm({ ...form, defense: e.target.value })} inputMode="numeric" /></Field>
            </div>

            <p style={{ margin: "var(--space-4) 0 var(--space-2)", color: "var(--accent)", font: "600 11px/1.3 'Fira Code', monospace", letterSpacing: ".08em", textTransform: "uppercase" }}>Награда</p>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))", gap: "var(--space-3)" }}>
              <Field label="Опыт"><input style={fieldStyle} value={form.xp_reward} onChange={(e) => setForm({ ...form, xp_reward: e.target.value })} inputMode="numeric" /></Field>
              <Field label="Золото мин."><input style={fieldStyle} value={form.gold_min} onChange={(e) => setForm({ ...form, gold_min: e.target.value })} inputMode="numeric" /></Field>
              <Field label="Золото макс."><input style={fieldStyle} value={form.gold_max} onChange={(e) => setForm({ ...form, gold_max: e.target.value })} inputMode="numeric" /></Field>
            </div>

            <div style={{ display: "flex", alignItems: "center", gap: "var(--space-3)", marginTop: "var(--space-4)" }}>
              <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 13 }}>
                <input type="checkbox" checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />
                Активен (встречается в мире)
              </label>
              <div style={{ marginLeft: "auto", display: "flex", gap: "var(--space-2)" }}>
                <button onClick={reset} style={{ padding: "8px 16px", background: "var(--panel-bg)", color: "var(--fg)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: 13 }}>Отмена</button>
                <button onClick={submit} style={{ padding: "8px 20px", background: "var(--accent)", color: "var(--accent-on)", border: "none", borderRadius: "var(--radius-md)", fontSize: 13, fontWeight: 600 }}>
                  {editingId ? "Сохранить" : "Создать"}
                </button>
              </div>
            </div>
          </div>
        )}

        <div className="panel-body" style={{ display: "flex", gap: "var(--space-2)", flexWrap: "wrap", alignItems: "center" }}>
          <select style={{ ...fieldStyle, maxWidth: 260 }} value={locFilter} onChange={(e) => { setLocFilter(e.target.value); setPage(1) }}>
            <option value="">Все локации</option>
            {locations.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
          </select>
          <button onClick={load} disabled={loading} style={{ padding: "8px 14px", background: "var(--panel-bg)", color: "var(--fg)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: 13 }}>
            {loading ? "…" : "Обновить"}
          </button>
        </div>
      </div>

      <div className="panel">
        <div className="panel-header">Список <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--muted)", fontWeight: 400, textTransform: "none", letterSpacing: 0 }}>страница {page} из {Math.max(1, Math.ceil(total / perPage))}</span></div>
        <div className="panel-body" style={{ padding: 0, overflowX: "auto" }}>
          <table className="decision-audit-table">
            <thead>
              <tr>
                <th style={{ textAlign: "left" }}>Монстр</th>
                <th style={{ textAlign: "left" }}>Локация</th>
                <th style={{ textAlign: "left" }}>Уровни</th>
                <th style={{ textAlign: "right" }}>HP</th>
                <th style={{ textAlign: "right" }}>Атака</th>
                <th style={{ textAlign: "right" }}>Защита</th>
                <th style={{ textAlign: "right" }}>Опыт</th>
                <th style={{ textAlign: "right" }}>Золото</th>
                <th style={{ textAlign: "right" }}>Действия</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id}>
                  <td>
                    <strong>{row.name}</strong>
                    {!row.is_active && <small style={{ color: "var(--danger)" }}>выключен</small>}
                  </td>
                  <td style={{ color: "var(--muted)", fontSize: 12 }}>{row.location_name ?? "—"}</td>
                  <td style={{ fontFamily: "var(--font-mono)", fontSize: 12 }}>{row.min_level}–{row.max_level}</td>
                  <td style={{ textAlign: "right", fontFamily: "var(--font-mono)", fontSize: 12 }}>{row.hp}</td>
                  <td style={{ textAlign: "right", fontFamily: "var(--font-mono)", fontSize: 12 }}>{row.attack_min}–{row.attack_max}</td>
                  <td style={{ textAlign: "right", fontFamily: "var(--font-mono)", fontSize: 12 }}>{row.defense}</td>
                  <td style={{ textAlign: "right", fontFamily: "var(--font-mono)", fontSize: 12 }}>{row.xp_reward}</td>
                  <td style={{ textAlign: "right", fontFamily: "var(--font-mono)", fontSize: 12 }}>{row.gold_min}–{row.gold_max}</td>
                  <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
                    <button onClick={() => startEdit(row)} style={{ padding: "4px 10px", marginRight: 6, background: "var(--panel-bg)", color: "var(--fg)", border: "1px solid var(--border)", borderRadius: "var(--radius-sm)", fontSize: 12 }}>Правка</button>
                    <button onClick={() => remove(row)} style={{ padding: "4px 10px", background: "transparent", color: "var(--danger)", border: "1px solid var(--danger)", borderRadius: "var(--radius-sm)", fontSize: 12 }}>Удалить</button>
                  </td>
                </tr>
              ))}
              {rows.length === 0 && (
                <tr><td colSpan={9} style={{ textAlign: "center", color: "var(--muted)", padding: "var(--space-5)" }}>{loading ? "Загрузка…" : "Ничего не найдено"}</td></tr>
              )}
            </tbody>
          </table>
        </div>
        {total > perPage && (
          <div style={{ display: "flex", gap: "var(--space-2)", justifyContent: "center", padding: "var(--space-3)", borderTop: "1px solid var(--border)" }}>
            <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1} style={{ padding: "6px 14px", background: "var(--panel-bg)", color: "var(--fg)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: 13 }}>← Назад</button>
            <button onClick={() => setPage((p) => p + 1)} disabled={page >= Math.ceil(total / perPage)} style={{ padding: "6px 14px", background: "var(--panel-bg)", color: "var(--fg)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: 13 }}>Вперёд →</button>
          </div>
        )}
      </div>
    </div>
  )
}

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
  const [deletingAll, setDeletingAll] = useState(false)

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
            <>
            <button
              type="button"
              aria-label="Удалить все ожидающие шаблоны по текущему фильтру"
              disabled={deletingAll}
              onClick={async () => {
                const scope = typeFilter ? `типа «${typeFilter}»` : "ВСЕ ожидающие шаблоны"
                if (!confirm(`Удалить ${total} шаблонов (${scope}) без возможности восстановления?`)) return
                setDeletingAll(true)
                try {
                  const res = await api.adminDeletePendingTemplates(typeFilter ? { template_type: typeFilter } : { all: true })
                  setGenMsg(`Удалено ожидающих шаблонов: ${res.deleted}`)
                  setPage(1)
                } catch (error: any) {
                  setGenMsg(error?.message || "Ошибка массового удаления")
                } finally {
                  setDeletingAll(false)
                  load()
                }
              }}
              style={{ padding: "4px 10px", background: "color-mix(in oklab, var(--danger), transparent 86%)", color: "var(--danger)", border: "1px solid var(--danger)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", cursor: deletingAll ? "wait" : "pointer" }}
            >
              {deletingAll ? "Удаляем…" : `Удалить всё отобранное (${total})`}
            </button>
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
            </>
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
  const active = tabs.find((tab) => tab.key === activeTab) ?? tabs[0]
  const sections = [...new Set(tabs.map((tab) => tab.section))]

  return (
    <section className="admin-observatory anim-fade-up" aria-labelledby="admin-observatory-title">
      <header className="admin-command-header">
        <div>
          <p className="admin-kicker"><span aria-hidden="true">◆</span> Командная палата</p>
          <h1 id="admin-observatory-title">Управление владением</h1>
          <p className="admin-command-intro">Наблюдайте за миром, распоряжайтесь доступом и ведите летопись без лишнего шума.</p>
        </div>
        <div className="admin-command-seal" aria-label="Привилегированный доступ">
          <span aria-hidden="true">♜</span>
          <div><b>Привилегированный доступ</b><small>Все действия применяются к живому миру</small></div>
        </div>
      </header>

      <div className="admin-command-layout">
        <nav className="admin-command-nav" aria-label="Разделы командной палаты">
          <div className="admin-nav-heading">Разделы</div>
          <div className="admin-nav-scroll" role="tablist" aria-orientation="vertical">
            {sections.map((section) => (
              <div className="admin-nav-group" key={section}>
                <p>{section}</p>
                {tabs.filter((tab) => tab.section === section).map((tab) => (
                  <button
                    key={tab.key}
                    id={`admin-tab-${tab.key}`}
                    className={`admin-command-tab ${activeTab === tab.key ? "active" : ""} ${tab.destructive ? "admin-command-tab-danger" : ""}`}
                    role="tab"
                    aria-selected={activeTab === tab.key}
                    aria-controls="admin-tab-panel"
                    tabIndex={activeTab === tab.key ? 0 : -1}
                    onClick={() => setActiveTab(tab.key)}
                  >
                    <span className="admin-tab-mark" aria-hidden="true">{tab.mark}</span>
                    <span>{tab.label}</span>
                  </button>
                ))}
              </div>
            ))}
          </div>
        </nav>

        <main id="admin-tab-panel" className="admin-command-content" role="tabpanel" aria-labelledby={`admin-tab-${active.key}`} tabIndex={-1}>
          <header className="admin-content-heading">
            <div>
              <p>{active.section}</p>
              <h2>{active.label}</h2>
            </div>
            {active.destructive && <span className="admin-danger-status" role="status">Требует осознанного действия</span>}
          </header>
          <div className="admin-panel-stage">
            {activeTab === "overview" && <OverviewPanel />}
            {activeTab === "users" && <UsersPanel />}
            {activeTab === "heroes" && <HeroesPanel />}
            {activeTab === "decision-audit" && <DecisionAuditPanel />}
            {activeTab === "narratives" && <NarrativesPanel />}
            {activeTab === "narrative-analytics" && <NarrativeAnalyticsPanel />}
            {activeTab === "moderation" && <ModerationPanel />}
            {activeTab === "suggestions" && <SuggestionsPanel />}
            {activeTab === "items" && <ItemsPanel />}
            {activeTab === "monsters" && <MonstersPanel />}
            {activeTab === "simulation" && <SimulationPanel />}
            {activeTab === "tests" && <TestsPanel />}
            {activeTab === "config" && <ConfigPanel />}
            {activeTab === "backup" && <BackupPanel />}
          </div>
        </main>
      </div>
    </section>
  )
}

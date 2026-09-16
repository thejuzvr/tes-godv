import { useEffect, useState } from "react"
import { api } from "@/lib/api"
import type { Pet } from "@/stores/gameStore"

interface PetHistoryEntry extends Pet {
  created_at: string | null
}

interface BrainData {
  brain_hash: string
  legacy: boolean
  generation: number
  archetype: string
  quirks: string[]
  traits: { trait: string; value: number; base: number | null }[]
  links: { a: string; b: string; weight: number; base_weight: number }[]
  decision_log: { day: number; hour: number | null; goal: string; utility: number | null; reasons: string[] }[]
  budget: { week: number; spent: number }
  stats: { total_kills: number; total_gold_earned: number; total_play_time_seconds: number; game_day: number; level: number; name: string }
}

const TRAIT_RU: Record<string, string> = {
  bravery: "Смелость", curiosity: "Любопытство", greed: "Жадность",
  sociability: "Общительность", tenacity: "Стойкость", caution: "Осторожность",
  patience: "Терпение", dexterity: "Ловкость", empathy: "Эмпатия",
}

const QUIRK_RU: Record<string, string> = {
  afraid_of_water: "💧 Боится воды", dawn_fisher: "🌅 Рыбак на рассвете",
  cup_collector: " чашек", night_thief: "🌙 Ночной вор",
  spider_panic: "🕷 Паукофоб", braggart: "📣 Хвастун",
  superstitious: "🔮 Суеверен", sweet_tooth: "🍰 Сладкоежка",
}
QUIRK_RU.cup_collector = "🏺 Коллекционер чашек"

const ARCHETYPE_RU: Record<string, string> = {
  wanderer: "Странник", warrior: "Воин", schemer: "Интриган",
  socialite: "Душа компании", hermit: "Отшельник", grinder: "Труженик",
}

const GOAL_RU: Record<string, string> = {
  complete_quest: "Квест", heal: "Лечение", rest: "Отдых", explore: "Исследование",
  fight: "Бой", shop: "Торговля", socialize: "Общение", travel: "Дорога",
  loot: "Добыча", fish: "🎣 Рыбалка", gather: "🌿 Сбор", steal: "🗡 Кража",
  break_in: "🔓 Взлом", pet_care: "🐾 Питомец", __rebirth__: "✦ Перерождение",
}

// Построение радара: 9 осей, текущие черты (заливка) + гено-база (пунктир)
function TraitRadar({ traits }: { traits: BrainData["traits"] }) {
  const size = 240
  const c = size / 2
  const r = 88
  const n = traits.length

  const point = (i: number, v: number) => {
    const angle = (Math.PI * 2 * i) / n - Math.PI / 2
    const rr = (v / 100) * r
    return [c + rr * Math.cos(angle), c + rr * Math.sin(angle)]
  }

  const poly = (get: (t: BrainData["traits"][number]) => number) =>
    traits.map((t, i) => point(i, get(t)).join(",")).join(" ")

  const hasBase = traits.some((t) => t.base != null)

  return (
    <svg viewBox={`0 0 ${size} ${size}`} style={{ width: "100%", maxWidth: 300, display: "block", margin: "0 auto" }}>
      {[0.25, 0.5, 0.75, 1].map((k) => (
        <circle key={k} cx={c} cy={c} r={r * k} fill="none" stroke="var(--border)" strokeWidth="1" />
      ))}
      {traits.map((t, i) => {
        const [x, y] = point(i, 100)
        return <line key={t.trait} x1={c} y1={c} x2={x} y2={y} stroke="var(--border)" strokeWidth="1" />
      })}
      {hasBase && (
        <polygon points={poly((t) => t.base ?? t.value)} fill="none" stroke="var(--muted)" strokeWidth="1.5" strokeDasharray="4 3" />
      )}
      <polygon points={poly((t) => t.value)} fill="color-mix(in oklab, var(--accent), transparent 75%)" stroke="var(--accent)" strokeWidth="2" />
      {traits.map((t, i) => {
        const [x, y] = point(i, 126)
        return (
          <text key={t.trait} x={x} y={y} textAnchor="middle" dominantBaseline="middle"
            fontSize="9" fill="var(--muted)" style={{ fontFamily: "var(--font-body)" }}>
            {TRAIT_RU[t.trait] ?? t.trait}
          </text>
        )
      })}
    </svg>
  )
}

// Граф микросвязей: узлы-черты на окружности, рёбра = вес (толщина, цвет)
function LinksGraph({ links }: { links: BrainData["links"] }) {
  const size = 260
  const c = size / 2
  const r = 92
  const nodes = Object.keys(TRAIT_RU)

  const pos = (trait: string) => {
    const i = nodes.indexOf(trait)
    const angle = (Math.PI * 2 * Math.max(0, i)) / nodes.length - Math.PI / 2
    return [c + r * Math.cos(angle), c + r * Math.sin(angle)]
  }

  return (
    <svg viewBox={`0 0 ${size} ${size}`} style={{ width: "100%", maxWidth: 320, display: "block", margin: "0 auto" }}>
      {links.map((l) => {
        const [x1, y1] = pos(l.a)
        const [x2, y2] = pos(l.b)
        const w = Math.abs(l.weight)
        const drifted = Math.abs(l.weight - l.base_weight) > 0.02
        return (
          <line key={`${l.a}~${l.b}`}
            x1={x1} y1={y1} x2={x2} y2={y2}
            stroke={l.weight >= 0 ? "var(--success)" : "var(--danger)"}
            strokeWidth={0.5 + w * 2.5}
            strokeOpacity={drifted ? 0.95 : 0.45}
            strokeLinecap="round">
            <title>{`${TRAIT_RU[l.a]} × ${TRAIT_RU[l.b]}: ${l.weight.toFixed(2)} (база ${l.base_weight.toFixed(2)})`}</title>
          </line>
        )
      })}
      {nodes.map((t) => {
        const [x, y] = pos(t)
        return (
          <g key={t}>
            <circle cx={x} cy={y} r={13} fill="var(--panel-bg)" stroke="var(--border)" strokeWidth="1.5" />
            <text x={x} y={y} textAnchor="middle" dominantBaseline="middle" fontSize="9" fill="var(--fg)" style={{ fontFamily: "var(--font-body)" }}>
              {(TRAIT_RU[t] ?? t).slice(0, 3)}
            </text>
          </g>
        )
      })}
    </svg>
  )
}

const PET_SPECIES: Record<string, { icon: string; name: string }> = {
  wolf: { icon: "🐺", name: "Волк" },
  owl: { icon: "🦉", name: "Сова" },
  cat: { icon: "🐈", name: "Кот" },
  lizard: { icon: "🦎", name: "Ящерица" },
}

const chipStyle = (active: boolean): React.CSSProperties => ({
  padding: "3px 10px",
  borderRadius: "var(--radius-pill)",
  fontSize: "var(--text-xs)",
  border: `1px solid ${active ? "var(--accent)" : "var(--border)"}`,
  background: active ? "var(--accent)" : "var(--bg-elevated)",
  color: active ? "var(--accent-on)" : "var(--fg)",
  cursor: "pointer",
  fontWeight: active ? 600 : 400,
})

export function AnalyticsPage() {
  const [brain, setBrain] = useState<BrainData | null>(null)
  const [petHistory, setPetHistory] = useState<PetHistoryEntry[] | null>(null)
  const [loading, setLoading] = useState(true)
  const [copied, setCopied] = useState<string | null>(null)
  const [goalFilter, setGoalFilter] = useState<string | null>(null)

  useEffect(() => {
    api.getBrain().then(setBrain).catch(() => setBrain(null)).finally(() => setLoading(false))
    api.getPetHistory().then((d) => setPetHistory(d.pets)).catch(() => setPetHistory(null))
  }, [])

  const copy = (text: string, label: string) => {
    navigator.clipboard?.writeText(text).then(() => {
      setCopied(label)
      setTimeout(() => setCopied(null), 1500)
    })
  }

  const shareSummary = () => {
    if (!brain) return
    const top = [...brain.traits].sort((a, b) => b.value - a.value).slice(0, 3)
      .map((t) => `${TRAIT_RU[t.trait] ?? t.trait} ${t.value}`).join(", ")
    const text = `🧠 Мозг героя «${brain.stats.name}» (TES Idle)\n` +
      `Поколение: ${brain.generation} · Архетип: ${ARCHETYPE_RU[brain.archetype] ?? brain.archetype}\n` +
      `Доминирующие черты: ${top}\n` +
      `День ${brain.stats.game_day} · Ур. ${brain.stats.level} · Убийств: ${brain.stats.total_kills}\n` +
      `Hash: ${brain.brain_hash.slice(0, 16)}…`
    copy(text, "share")
  }

  if (loading) {
    return (
      <div className="anim-fade-up">
        <h1 style={{ fontFamily: "var(--font-display)", fontSize: "var(--text-2xl)", fontWeight: 800, marginBottom: "var(--space-4)" }}>Аналитика</h1>
        <div className="panel"><div className="panel-body" style={{ textAlign: "center", color: "var(--muted)", padding: 48 }}>Загрузка…</div></div>
      </div>
    )
  }

  if (!brain) {
    return (
      <div className="anim-fade-up">
        <h1 style={{ fontFamily: "var(--font-display)", fontSize: "var(--text-2xl)", fontWeight: 800, marginBottom: "var(--space-4)" }}>Аналитика</h1>
        <div className="panel"><div className="panel-body" style={{ textAlign: "center", color: "var(--muted)", padding: 48 }}>
          🧠 Герой не найден
        </div></div>
      </div>
    )
  }

  const budgetLeft = Math.max(0, 10 - (brain.budget.spent || 0))
  // Хроника решений: фильтр по цели, свежие сверху; без лимита — скролл внутри панели
  const decisionLog = goalFilter
    ? [...brain.decision_log].reverse().filter((d) => d.goal === goalFilter)
    : [...brain.decision_log].reverse()

  return (
    <div className="anim-fade-up">
      <div style={{ marginBottom: "var(--space-6)" }}>
        <h1 style={{ fontFamily: "var(--font-display)", fontSize: "var(--text-2xl)", fontWeight: 800, letterSpacing: "-0.02em", marginBottom: "var(--space-2)" }}>Аналитика</h1>
        <p style={{ color: "var(--muted)", fontSize: "var(--text-sm)" }}>Уникальный мозг героя «{brain.stats.name}» — черты, связи и хроника решений</p>
      </div>

      {/* Hash-паспорт */}
      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "var(--space-2)" }}>
          <span>🧠 Паспорт мозга</span>
          <span style={{ display: "flex", gap: "var(--space-2)", flexWrap: "wrap" }}>
            <span style={{ padding: "2px 10px", borderRadius: "var(--radius-pill)", background: "color-mix(in oklab, var(--xp), transparent 85%)", color: "var(--xp)", fontSize: "var(--text-xs)", fontWeight: 600 }}>
              Поколение {brain.generation}
            </span>
            <span style={{ padding: "2px 10px", borderRadius: "var(--radius-pill)", background: "color-mix(in oklab, var(--mp), transparent 85%)", color: "var(--mp)", fontSize: "var(--text-xs)", fontWeight: 600 }}>
              {ARCHETYPE_RU[brain.archetype] ?? brain.archetype}
            </span>
          </span>
        </div>
        <div className="panel-body">
          <div style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)", wordBreak: "break-all", marginBottom: "var(--space-3)" }}>
            {brain.brain_hash}
          </div>
          <div style={{ display: "flex", gap: "var(--space-2)", flexWrap: "wrap", alignItems: "center" }}>
            <button onClick={() => copy(brain.brain_hash, "hash")}
              style={{ padding: "6px 14px", borderRadius: "var(--radius-md)", border: "1px solid var(--border)", background: "var(--panel-bg)", color: "var(--fg)", cursor: "pointer", fontSize: "var(--text-xs)" }}>
              {copied === "hash" ? "✓ Скопировано" : "Копировать hash"}
            </button>
            <button onClick={shareSummary}
              style={{ padding: "6px 14px", borderRadius: "var(--radius-md)", border: "none", background: "var(--accent)", color: "var(--accent-on)", cursor: "pointer", fontSize: "var(--text-xs)", fontWeight: 600 }}>
              {copied === "share" ? "✓ Сводка в буфере" : "Поделиться сводкой"}
            </button>
            <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
              Пластичность: осталось {budgetLeft.toFixed(1)} п. (неделя {brain.budget.week})
            </span>
          </div>
          {brain.legacy && (
            <div style={{ marginTop: "var(--space-2)", fontSize: "var(--text-xs)", color: "var(--warn)" }}>
              Герой создан до эры Мозга — сравнение с гено-базой недоступно.
            </div>
          )}
          {brain.quirks.length > 0 && (
            <div style={{ marginTop: "var(--space-3)", display: "flex", gap: 6, flexWrap: "wrap" }}>
              {brain.quirks.map((q) => (
                <span key={q} style={{ padding: "3px 10px", borderRadius: "var(--radius-pill)", border: "1px solid var(--border)", fontSize: "var(--text-xs)", color: "var(--fg)", background: "var(--bg-elevated)" }}>
                  {QUIRK_RU[q] ?? q}
                </span>
              ))}
            </div>
          )}
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))", gap: "var(--space-4)", marginBottom: "var(--space-4)" }}>
        {/* Радар черт */}
        <div className="panel">
          <div className="panel-header">Радар черт {brain.traits.some((t) => t.base != null) && <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontWeight: 400 }}>· пунктир — гено-база</span>}</div>
          <div className="panel-body">
            <TraitRadar traits={brain.traits} />
            <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: "var(--space-1) var(--space-3)", marginTop: "var(--space-3)" }}>
              {brain.traits.map((t) => (
                <div key={t.trait} style={{ display: "flex", justifyContent: "space-between", fontSize: "var(--text-xs)" }}>
                  <span style={{ color: "var(--muted)" }}>{TRAIT_RU[t.trait] ?? t.trait}</span>
                  <span style={{ fontFamily: "var(--font-mono)", color: "var(--fg)" }}>{t.value}</span>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Граф связей */}
        <div className="panel">
          <div className="panel-header">Микросвязи <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontWeight: 400 }}>· толщина = сила · яркие = изменились опытом</span></div>
          <div className="panel-body">
            <LinksGraph links={brain.links} />
            <div style={{ display: "flex", gap: "var(--space-3)", justifyContent: "center", fontSize: "var(--text-xs)", color: "var(--muted)" }}>
              <span><span style={{ color: "var(--success)" }}>—</span> усиливающие</span>
              <span><span style={{ color: "var(--danger)" }}>—</span> подавляющие</span>
            </div>
          </div>
        </div>
      </div>

      {/* Хроника решений: фильтры по целям + скролл всего лога */}
      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">Хроника решений <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontWeight: 400 }}>· «почему герой выбрал X»</span></div>
        <div className="panel-body">
          {brain.decision_log.length === 0 ? (
            <div style={{ textAlign: "center", color: "var(--muted)", padding: 24, fontSize: "var(--text-sm)" }}>
              Мозг ещё не принимал решений — они появятся после первых тиков.
            </div>
          ) : (
            <>
              {(() => {
                const counts = new Map<string, number>()
                for (const d of brain.decision_log) counts.set(d.goal, (counts.get(d.goal) || 0) + 1)
                const goals = [...counts.entries()].sort((a, b) => b[1] - a[1])
                return (
                  <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: "var(--space-3)" }}>
                    <button type="button" onClick={() => setGoalFilter(null)}
                      style={chipStyle(goalFilter === null)}>
                      Все · {brain.decision_log.length}
                    </button>
                    {goals.map(([goal, n]) => (
                      <button type="button" key={goal} onClick={() => setGoalFilter(goal === goalFilter ? null : goal)}
                        style={chipStyle(goalFilter === goal)}>
                        {GOAL_RU[goal] ?? goal} · {n}
                      </button>
                    ))}
                  </div>
                )
              })()}
              <div style={{ maxHeight: 420, overflowY: "auto", overscrollBehavior: "contain" }}>
                {decisionLog.map((d, i) => (
                  <div key={`${d.day}-${d.hour ?? "x"}-${i}`} style={{
                    display: "flex", gap: "var(--space-3)", alignItems: "baseline",
                    padding: "var(--space-2) 0",
                    borderBottom: i < decisionLog.length - 1 ? "1px solid var(--border)" : "none",
                  }}>
                    <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)", whiteSpace: "nowrap" }}>
                      День {d.day}{d.hour != null ? `, ${d.hour}ч` : ""}
                    </span>
                    <span style={{ fontSize: "var(--text-sm)", fontWeight: 600, color: d.goal === "__rebirth__" ? "var(--xp)" : "var(--fg)", whiteSpace: "nowrap" }}>
                      {GOAL_RU[d.goal] ?? d.goal}
                    </span>
                    <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)", flex: 1, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                      {(d.reasons || []).join(" · ") || (d.utility != null ? `utility ${d.utility}` : "")}
                    </span>
                    {d.utility != null && (
                      <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--accent)" }}>
                        {d.utility.toFixed(2)}
                      </span>
                    )}
                  </div>
                ))}
                {decisionLog.length === 0 && (
                  <div style={{ textAlign: "center", color: "var(--muted)", padding: 24, fontSize: "var(--text-sm)" }}>
                    Решений такой цели в логе нет.
                  </div>
                )}
              </div>
              <div style={{ marginTop: "var(--space-2)", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)", textAlign: "right" }}>
                Показано {decisionLog.length} из {brain.decision_log.length} (лог хранит последние 50)
              </div>
            </>
          )}
        </div>
      </div>

      {/* История питомцев (P-1) */}
      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">🐾 История питомцев <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontWeight: 400 }}>· те, кто ушёл навсегда</span></div>
        <div className="panel-body">
          {petHistory === null ? (
            <div style={{ fontSize: "var(--text-sm)", color: "var(--muted)" }}>История недоступна — обнови страницу.</div>
          ) : petHistory.length === 0 ? (
            <div style={{ fontSize: "var(--text-sm)", color: "var(--muted)", lineHeight: 1.6 }}>
              Пока никто не уходил. Питомец покидает героя, только если лояльность упала до нуля.
            </div>
          ) : (
            petHistory.map((p) => {
              const sp = PET_SPECIES[p.species] || { icon: "🐾", name: p.species }
              const days = p.created_at
                ? Math.max(1, Math.round((Date.now() - new Date(p.created_at).getTime()) / 86400000))
                : null
              return (
                <div key={p.id} style={{
                  display: "flex", gap: "var(--space-3)", alignItems: "center",
                  padding: "var(--space-2) 0",
                  borderBottom: "1px solid var(--border)",
                }}>
                  <span style={{ fontSize: 20 }}>{sp.icon}</span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: "var(--text-sm)", fontWeight: 600 }}>
                      {sp.name} · {p.name}
                    </div>
                    <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>
                      {days != null ? `Прожил в миру героя ~${days} дн.` : "Верность иссякла"}
                    </div>
                  </div>
                  <span style={{
                    fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)",
                    color: "var(--muted)", whiteSpace: "nowrap",
                  }}>
                    верность 0
                  </span>
                </div>
              )
            })
          )}
        </div>
      </div>

      {/* Статистика */}
      <div className="panel">
        <div className="panel-header">Статистика героя</div>
        <div className="panel-body">
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))", gap: "var(--space-3)" }}>
            {[
              { label: "Уровень", value: brain.stats.level },
              { label: "Игровой день", value: brain.stats.game_day },
              { label: "Убийств", value: brain.stats.total_kills },
              { label: "Золота заработано", value: brain.stats.total_gold_earned },
              { label: "Время в мире", value: `${Math.round(brain.stats.total_play_time_seconds / 60)} мин` },
              { label: "Решений в логе", value: brain.decision_log.length },
            ].map((s) => (
              <div key={s.label} style={{ padding: "var(--space-2) var(--space-3)", background: "var(--bg-elevated)", borderRadius: "var(--radius-md)" }}>
                <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>{s.label}</div>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-lg)", fontWeight: 700, color: "var(--fg)" }}>{s.value}</div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}

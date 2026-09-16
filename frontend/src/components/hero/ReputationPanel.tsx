import { useEffect, useState } from "react"
import { api } from "@/lib/api"

interface Reputation {
  faction: string
  value: number
  level: string
}

/* Уровни из бэка: английские ключи (law.ex) и русское дефолтное значение схемы.
   Нормализуем в классы .rep-* и человеческие подписи. */
const LEVELS: Record<string, { cls: string; label: string }> = {
  hostile: { cls: "hostile", label: "Враг" },
  "враг": { cls: "hostile", label: "Враг" },
  "враждебность": { cls: "hostile", label: "Враждебность" },
  unfriendly: { cls: "unfriendly", label: "Враждебность" },
  neutral: { cls: "neutral", label: "Нейтралитет" },
  "нейтралитет": { cls: "neutral", label: "Нейтралитет" },
  friendly: { cls: "friendly", label: "Дружелюбие" },
  allied: { cls: "allied", label: "Союзник" },
}

const normLevel = (level: string) => LEVELS[(level || "").toLowerCase()] || LEVELS["нейтралитет"]

/* Пороги уровня с бэка (Law.rep_cfg thresholds); value → процент для бара */
const THRESHOLDS: Record<string, number> = {
  hostile: -50, unfriendly: -1, neutral: 25, friendly: 75, allied: 100,
}

const LEVEL_ORDER = ["hostile", "unfriendly", "neutral", "friendly", "allied"]

/* value ∈ [-100, 100] → процент шкалы 0..100 */
function valueToPercent(value: number): number {
  return Math.round(((value + 100) / 200) * 100)
}

/* Подпись «до следующего уровня»: сколько очков осталось */
function nextLevelHint(level: string, value: number): string | null {
  const idx = LEVEL_ORDER.indexOf(level)
  if (idx < 0 || idx >= LEVEL_ORDER.length - 1) return null
  const nextKey = LEVEL_ORDER[idx + 1]
  const need = (THRESHOLDS[nextKey] ?? 0) - value
  return need > 0 ? `+${need} до «${LEVELS[nextKey].label}»` : null
}

const barColor = (cls: string) =>
  cls === "hostile" ? "var(--danger)" :
  cls === "unfriendly" ? "var(--warn)" :
  cls === "neutral" ? "var(--muted)" :
  cls === "friendly" ? "var(--success)" : "var(--accent)"

/* ─── Reputation Panel — P-3: значения, уровень, прогресс к следующему ─── */
export function ReputationPanel({ refreshTrigger = 0 }: { refreshTrigger?: number }) {
  const [reps, setReps] = useState<Reputation[] | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    setFailed(false)
    api.getReputations()
      .then((d) => setReps(d.reputations))
      .catch(() => setFailed(true))
  }, [refreshTrigger])

  return (
    <div className="panel">
      <div className="panel-header">
        <div className="flex items-center gap-2">
          <span className="panel-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
          </span>
          Репутация
        </div>
      </div>
      <div className="panel-body">
        {failed ? (
          <div style={{ fontSize: "var(--text-sm)", color: "var(--muted)" }}>Репутация недоступна — обнови страницу.</div>
        ) : reps === null ? (
          <div style={{ fontSize: "var(--text-sm)", color: "var(--muted)" }}>Загрузка…</div>
        ) : reps.length === 0 ? (
          <div style={{ fontSize: "var(--text-sm)", color: "var(--muted)", lineHeight: 1.6 }}>
            Репутация нейтральна во всех фракциях. Квесты и победы над чудовищами её поднимают, преступления — роняют.
          </div>
        ) : (
          reps.map((r, i) => {
            const lv = normLevel(r.level)
            const pct = valueToPercent(r.value)
            const hint = nextLevelHint(lv.cls, r.value)
            return (
              <div key={i} style={{ marginBottom: i < reps.length - 1 ? "var(--space-3)" : 0 }}>
                <div className="rep-bar">
                  <span className="rep-faction">{r.faction}</span>
                  <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)" }}>
                    {r.value > 0 ? `+${r.value}` : r.value}
                  </span>
                  <span className={`rep-level rep-${lv.cls}`}>{lv.label}</span>
                </div>
                <div style={{ height: 5, background: "color-mix(in oklab, var(--fg), transparent 92%)", borderRadius: 3, overflow: "hidden", marginTop: 4 }}>
                  <div style={{ height: "100%", width: `${pct}%`, background: barColor(lv.cls), borderRadius: 3, transition: "width 0.4s" }} />
                </div>
                {hint && (
                  <div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)", marginTop: 3 }}>{hint}</div>
                )}
              </div>
            )
          })
        )}
      </div>
    </div>
  )
}

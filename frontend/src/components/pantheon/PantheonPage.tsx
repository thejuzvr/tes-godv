import { useState, useEffect, useCallback } from "react"
import { api } from "@/lib/api"
import { formatNumber, formatTime } from "@/lib/utils"

interface PantheonEntry {
  rank: number
  hero_name: string
  hero_level: number
  value: number
}

type Metric = "kills" | "gold" | "time"

const metricConfig = {
  kills: { label: "Убийства", icon: "⚔️", api: () => api.getPantheonKills(), format: (v: number) => formatNumber(v) },
  gold: { label: "Золото", icon: "🪙", api: () => api.getPantheonGold(), format: (v: number) => `${formatNumber(v)} золота` },
  time: { label: "Время", icon: "⏱️", api: () => api.getPantheonTime(), format: (v: number) => formatTime(v) },
}

const avatarColors = [
  "var(--danger)", "var(--accent)", "var(--xp)", "var(--mp)",
  "#8b5cf6", "#ec4899", "#14b8a6", "#f59e0b", "#6366f1", "#22c55e",
]

function getAvatarColor(name: string): string {
  let hash = 0
  for (let i = 0; i < name.length; i++) {
    hash = name.charCodeAt(i) + ((hash << 5) - hash)
  }
  return avatarColors[Math.abs(hash) % avatarColors.length]
}

// Top-3 podium styling: vertical cards with medal frames
const podiumStyles: Record<number, { medal: string; border: string; tint: string; labelColor: string; order: number }> = {
  1: { medal: "🥇", border: "#d4af37", tint: "color-mix(in oklab, #d4af37, transparent 88%)", labelColor: "#d4af37", order: 2 },
  2: { medal: "🥈", border: "#c0c0c0", tint: "color-mix(in oklab, #c0c0c0, transparent 90%)", labelColor: "#c0c0c0", order: 1 },
  3: { medal: "🥉", border: "#cd7f32", tint: "color-mix(in oklab, #cd7f32, transparent 89%)", labelColor: "#cd7f32", order: 3 },
}

export function PantheonPage() {
  const [metric, setMetric] = useState<Metric>("kills")
  const [data, setData] = useState<PantheonEntry[]>([])
  const [loading, setLoading] = useState(true)

  const fetchData = useCallback(() => {
    setLoading(true)
    metricConfig[metric].api().then(setData).catch(() => setData([])).finally(() => setLoading(false))
  }, [metric])

  useEffect(() => { fetchData() }, [fetchData])

  // Auto-refresh every 30 seconds
  useEffect(() => {
    const interval = setInterval(fetchData, 30000)
    return () => clearInterval(interval)
  }, [fetchData])

  const podium = data.filter(e => e.rank >= 1 && e.rank <= 3)
    .map(e => ({ entry: e, style: podiumStyles[e.rank] }))
    .sort((a, b) => a.style.order - b.style.order) // display: 2nd, 1st, 3rd
  const rest = data.filter(e => e.rank > 3)

  return (
    <div className="anim-fade-up">
      <div style={{ marginBottom: "var(--space-6)" }}>
        <h1 style={{ fontFamily: "var(--font-display)", fontSize: "var(--text-2xl)", fontWeight: 800, letterSpacing: "-0.02em", marginBottom: "var(--space-2)" }}>Пантеон</h1>
        <p style={{ color: "var(--muted)", fontSize: "var(--text-sm)" }}>Рейтинг героев по всему Тамриэлю</p>
      </div>

      <div style={{ display: "flex", gap: "var(--space-2)", marginBottom: "var(--space-4)" }}>
        {(Object.keys(metricConfig) as Metric[]).map((m) => (
          <button key={m} onClick={() => setMetric(m)}
            style={{ padding: "6px 14px", borderRadius: "var(--radius-pill)", fontSize: "var(--text-sm)", fontWeight: 500, border: "none", cursor: "pointer", transition: "all 150ms",
              background: metric === m ? "var(--accent)" : "var(--panel-bg)", color: metric === m ? "var(--accent-on)" : "var(--muted)" }}>
            {metricConfig[m].icon} {metricConfig[m].label}
          </button>
        ))}
      </div>

      <div className="panel">
        <div className="panel-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span>Топ героев — {metricConfig[metric].label}</span>
          <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
            {data.length} героев
          </span>
        </div>
        <div className="panel-body">
          {loading ? (
            <div style={{ textAlign: "center", color: "var(--muted)", padding: 32 }}>Загрузка…</div>
          ) : data.length === 0 ? (
            <div style={{ textAlign: "center", color: "var(--muted)", padding: 32 }}>
              <div style={{ fontSize: 32, marginBottom: "var(--space-2)" }}>🏆</div>
              Нет данных для отображения
            </div>
          ) : (
            <div>
              {/* Top-3 podium: silver | gold | bronze, vertical cards */}
              {podium.length > 0 && (
                <div style={{
                  display: "grid",
                  gridTemplateColumns: "repeat(3, 1fr)",
                  gap: "var(--space-3)",
                  alignItems: "end",
                  marginBottom: "var(--space-5)",
                  paddingBottom: "var(--space-5)",
                  borderBottom: "1px solid var(--border)",
                }}>
                  {podium.map(({ entry, style }) => (
                    <div key={entry.rank} style={{
                      display: "flex", flexDirection: "column", alignItems: "center",
                      gap: "var(--space-1)", padding: "var(--space-4) var(--space-2) var(--space-3)",
                      borderRadius: "var(--radius-lg)",
                      border: `2px solid ${style.border}`,
                      background: style.tint,
                      order: style.order,
                      transition: "transform 150ms",
                    }}
                      onMouseEnter={e => (e.currentTarget.style.transform = "translateY(-3px)")}
                      onMouseLeave={e => (e.currentTarget.style.transform = "none")}>
                      <span style={{ fontSize: entry.rank === 1 ? 34 : 28, lineHeight: 1 }}>{style.medal}</span>
                      <span style={{
                        width: 44, height: 44, borderRadius: "50%", display: "flex",
                        alignItems: "center", justifyContent: "center",
                        fontSize: "var(--text-base)", fontWeight: 700,
                        background: getAvatarColor(entry.hero_name), color: "#fff",
                        border: `2px solid ${style.border}`,
                      }}>
                        {entry.hero_name.charAt(0).toUpperCase()}
                      </span>
                      <span style={{
                        fontWeight: 700, fontSize: "var(--text-sm)", color: "var(--fg)",
                        maxWidth: "100%", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
                      }}>
                        {entry.hero_name}
                      </span>
                      <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
                        Ур. {entry.hero_level}
                      </span>
                      <span style={{
                        fontFamily: "var(--font-mono)", fontWeight: 700, fontSize: entry.rank === 1 ? "var(--text-base)" : "var(--text-sm)",
                        color: style.labelColor, fontVariantNumeric: "tabular-nums",
                      }}>
                        {metricConfig[metric].format(entry.value)}
                      </span>
                    </div>
                  ))}
                </div>
              )}

              {/* Ranks 4+ */}
              {rest.map((entry) => (
                <div key={entry.rank} style={{
                  display: "flex", alignItems: "center", gap: "var(--space-3)",
                  padding: "var(--space-2) 0",
                  borderBottom: "1px solid var(--border)",
                }}>
                  <span style={{
                    width: 32, height: 32, display: "flex", alignItems: "center", justifyContent: "center",
                    borderRadius: "50%", fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: "var(--text-xs)",
                    background: "var(--panel-bg)", color: "var(--muted)", flexShrink: 0,
                  }}>
                    {entry.rank}
                  </span>

                  <span style={{
                    width: 32, height: 32, borderRadius: "50%", display: "flex",
                    alignItems: "center", justifyContent: "center", fontSize: "var(--text-xs)",
                    fontWeight: 600, background: getAvatarColor(entry.hero_name),
                    color: "#fff", flexShrink: 0,
                  }}>
                    {entry.hero_name.charAt(0).toUpperCase()}
                  </span>

                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontWeight: 500, fontSize: "var(--text-sm)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                      {entry.hero_name}
                    </div>
                    <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
                      Уровень {entry.hero_level}
                    </div>
                  </div>

                  <span style={{
                    fontFamily: "var(--font-mono)", fontWeight: 600, fontSize: "var(--text-sm)",
                    fontVariantNumeric: "tabular-nums", color: "var(--fg)",
                  }}>
                    {metricConfig[metric].format(entry.value)}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

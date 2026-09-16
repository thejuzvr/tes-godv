import { useState } from "react"
import { Zap, Sparkles, Heart, Compass, Scroll, CloudRain } from "lucide-react"

/* ─── God Panel — Небесный Алтарь: божественные вмешательства ─── */
export function GodPanel({ onAction, hero }: { onAction: (t: string) => Promise<string | null>; hero: any }) {
  const [cooldown, setCooldown] = useState(false)
  const [lastAction, setLastAction] = useState<string | null>(null)
  const [narrative, setNarrative] = useState<string | null>(null)

  const actions = [
    { type: "encourage", icon: <Sparkles size={16} />, label: "Вдохновить", color: "var(--accent)", desc: "+15 мораль" },
    { type: "punish", icon: <Zap size={16} />, label: "Наказать", color: "var(--danger)", desc: "−10 мораль" },
    { type: "heal", icon: <Heart size={16} />, label: "Исцелить", color: "var(--success)", desc: "+30 HP" },
    { type: "direct", icon: <Compass size={16} />, label: "Направить", color: "var(--mp)", desc: "Смена цели" },
    { type: "quest", icon: <Scroll size={16} />, label: "Задание", color: "var(--gold)", desc: "Новый квест" },
    { type: "weather", icon: <CloudRain size={16} />, label: "Погода", color: "#38bdf8", desc: "Знак небес" },
  ]

  const handleClick = async (type: string, label: string) => {
    if (cooldown) return
    setCooldown(true)
    setLastAction(label)
    setNarrative(null)
    try {
      const text = await onAction(type)
      setNarrative(text)
    } finally {
      setTimeout(() => setCooldown(false), 5000)
    }
  }

  const soulPct = Math.min(100, Math.max(0, Math.round(hero.soul_energy || 0)))

  return (
    <div className="panel god-panel fantasy-window parchment-glow">
      <div className="panel-header" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div className="flex items-center gap-2">
          <span className="panel-icon" style={{ color: "var(--accent)" }}>
            <Sparkles size={15} />
          </span>
          <span style={{ fontFamily: "var(--font-display)", fontStyle: "italic", fontWeight: 700, fontSize: 16 }}>
            Алтарь Богов
          </span>
        </div>
        <span
          style={{
            fontFamily: "var(--font-mono)",
            fontSize: 10,
            textTransform: "uppercase",
            letterSpacing: "0.1em",
            color: "var(--muted)",
          }}
        >
          Воля небес
        </span>
      </div>

      <div className="panel-body" style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        {/* Soul Energy Vessel */}
        <div
          className="anim-celestial-pulse"
          style={{
            padding: "10px 14px",
            background: "color-mix(in srgb, var(--surface-raised) 90%, black)",
            borderRadius: "var(--radius-md)",
            border: "1px solid color-mix(in srgb, var(--border) 70%, var(--xp) 40%)",
          }}
        >
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 6 }}>
            <span
              style={{
                fontFamily: "var(--font-mono)",
                fontSize: 10,
                textTransform: "uppercase",
                letterSpacing: "0.08em",
                color: "var(--xp)",
                display: "flex",
                alignItems: "center",
                gap: 6,
              }}
            >
              <span style={{ display: "inline-block", width: 6, height: 6, borderRadius: "50%", background: "var(--xp)", boxShadow: "0 0 8px var(--xp)" }} />
              Сила Душ
            </span>
            <span
              style={{
                fontFamily: "var(--font-mono)",
                fontSize: 12,
                fontWeight: 700,
                color: "var(--xp)",
              }}
            >
              {soulPct}%
            </span>
          </div>
          <div
            style={{
              height: 6,
              background: "color-mix(in srgb, var(--bg) 90%, black)",
              borderRadius: "var(--radius-pill)",
              overflow: "hidden",
            }}
          >
            <div
              style={{
                height: "100%",
                width: `${soulPct}%`,
                background: "linear-gradient(90deg, #4c2882, var(--xp), var(--accent))",
                boxShadow: "0 0 10px color-mix(in srgb, var(--xp) 60%, transparent)",
                borderRadius: "var(--radius-pill)",
                transition: "width 0.5s ease",
              }}
            />
          </div>
        </div>

        {/* 6 Intervention Action Cards */}
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(2, 1fr)",
            gap: 8,
          }}
        >
          {actions.map(({ type, icon, label, color, desc }) => (
            <button
              key={type}
              onClick={() => handleClick(type, label)}
              disabled={cooldown}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                padding: "8px 12px",
                background: "color-mix(in srgb, var(--surface) 90%, black)",
                border: "1px solid color-mix(in srgb, var(--border) 80%, transparent)",
                borderRadius: "var(--radius-sm)",
                color: "var(--fg)",
                cursor: cooldown ? "not-allowed" : "pointer",
                opacity: cooldown ? 0.5 : 1,
                transition: "all 0.18s ease",
                textAlign: "left",
              }}
              onMouseEnter={(e) => {
                if (!cooldown) {
                  e.currentTarget.style.borderColor = color
                  e.currentTarget.style.boxShadow = `0 0 14px color-mix(in srgb, ${color} 35%, transparent)`
                  e.currentTarget.style.transform = "translateY(-1px)"
                }
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.borderColor = "color-mix(in srgb, var(--border) 80%, transparent)"
                e.currentTarget.style.boxShadow = "none"
                e.currentTarget.style.transform = "translateY(0)"
              }}
            >
              <div
                style={{
                  width: 28,
                  height: 28,
                  borderRadius: "var(--radius-sm)",
                  background: `color-mix(in srgb, ${color} 15%, transparent)`,
                  color: color,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  flexShrink: 0,
                }}
              >
                {icon}
              </div>
              <div style={{ minWidth: 0, flex: 1 }}>
                <div style={{ fontFamily: "var(--font-mono)", fontSize: 11, fontWeight: 600, letterSpacing: "0.02em" }}>
                  {label}
                </div>
                <div style={{ fontSize: 9, color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
                  {desc}
                </div>
              </div>
            </button>
          ))}
        </div>

        {/* Recent Intervention Log */}
        {lastAction && (
          <div
            style={{
              paddingTop: 10,
              borderTop: "1px dashed var(--border)",
              display: "flex",
              flexDirection: "column",
              gap: 6,
            }}
          >
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ fontSize: 10, color: "var(--muted)", fontFamily: "var(--font-mono)", textTransform: "uppercase", letterSpacing: "0.08em" }}>
                Последнее знамение:
              </span>
              <span style={{ fontSize: 10, color: "var(--accent)", fontFamily: "var(--font-mono)" }}>
                «{lastAction}»
              </span>
            </div>
            {narrative && (
              <div
                style={{
                  padding: "8px 12px",
                  background: "color-mix(in srgb, var(--accent) 10%, var(--surface))",
                  borderLeft: "2px solid var(--accent)",
                  borderRadius: "0 var(--radius-sm) var(--radius-sm) 0",
                  fontSize: 12,
                  fontStyle: "italic",
                  fontFamily: "var(--font-body)",
                  lineHeight: 1.5,
                  color: "var(--fg)",
                }}
              >
                {narrative}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

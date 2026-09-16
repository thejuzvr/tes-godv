import { StatBar } from "@/components/ui/StatBar"
import { formatNumber } from "@/lib/utils"
import { Shield } from "lucide-react"

const STATE_INFO: Record<string, { label: string; icon: string; color: string }> = {
  fighting: { label: "Бьётся насмерть", icon: "⚔️", color: "var(--danger)" },
  traveling: { label: "В пути по тракту", icon: "🧭", color: "var(--accent)" },
  resting: { label: "Отдыхает у костра", icon: "🏕️", color: "var(--success)" },
  exploring: { label: "Исследует окрестности", icon: "🔍", color: "var(--mp)" },
  shopping: { label: "Торгует в лавке", icon: "🛒", color: "var(--gold)" },
  jailed: { label: "В темнице", icon: "⛓️", color: "var(--warn)" },
  dead: { label: "Ожидает возрождения", icon: "💀", color: "var(--danger)" },
  fishing: { label: "Удит рыбу", icon: "🎣", color: "#38bdf8" },
  gathering: { label: "Собирает травы", icon: "🌿", color: "var(--success)" },
  stealing: { label: "Замышляет кражу", icon: "🤫", color: "#c084fc" },
  breaking_in: { label: "Взламывает замок", icon: "🗝️", color: "#f59e0b" },
  pet_care: { label: "Заботится о питомце", icon: "🐾", color: "#f472b6" },
}

/* ─── Hero Panel — витрина героя: благородный медальон + жизненные силы + кошель ─── */
export function HeroPanel({ hero }: { hero: any }) {
  // Награда за голову (LawSystem): state_data.law.bounties — сумма по фракциям
  let bounty = 0
  let generation = hero.generation || 1
  try {
    const sd = JSON.parse(hero.state_data || "{}")
    const law = sd?.law
    bounty = law?.bounties
      ? Object.values<number>(law.bounties).reduce((a: number, b: number) => a + b, 0)
      : 0
    if (sd?.death?.generation) {
      generation = sd.death.generation
    }
  } catch { /* нет state_data — нет награды */ }

  const cap = (s: string) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s)
  const stateMeta = STATE_INFO[hero.state] || { label: hero.state || "Действует", icon: "✨", color: "var(--accent)" }

  return (
    <div className="panel hero-panel fantasy-window parchment-glow">
      <div className="panel-body">
        <div className="hero-identity" style={{ display: "flex", alignItems: "center", gap: 16 }}>
          {/* Ornate Medallion Avatar */}
          <div style={{ position: "relative", flexShrink: 0 }}>
            <div
              className="hero-avatar"
              style={{
                width: 58,
                height: 58,
                borderRadius: "50%",
                background: "radial-gradient(circle at 35% 35%, color-mix(in srgb, var(--surface-raised) 80%, black), var(--bg))",
                border: "2px solid color-mix(in srgb, var(--accent) 70%, transparent)",
                boxShadow: "0 0 16px color-mix(in srgb, var(--accent) 30%, transparent)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontFamily: "var(--font-display)",
                fontSize: 26,
                fontWeight: 700,
                color: "var(--accent)",
                fontStyle: "italic",
              }}
            >
              {hero.name ? hero.name[0].toUpperCase() : "Д"}
            </div>
            <span
              style={{
                position: "absolute",
                bottom: -4,
                right: -4,
                padding: "1px 6px",
                borderRadius: "var(--radius-pill)",
                background: "var(--accent)",
                color: "var(--accent-on)",
                fontFamily: "var(--font-mono)",
                fontSize: 9,
                fontWeight: 700,
                letterSpacing: "0.04em",
                boxShadow: "0 2px 6px rgba(0,0,0,0.5)",
              }}
            >
              {hero.level}
            </span>
          </div>

          {/* Titles & Lore Identity */}
          <div className="hero-titles" style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: "flex", alignItems: "baseline", gap: 8, flexWrap: "wrap" }}>
              <span
                className="hero-name"
                style={{
                  fontFamily: "var(--font-display)",
                  fontSize: 24,
                  fontWeight: 700,
                  fontStyle: "italic",
                  color: "var(--fg)",
                  lineHeight: 1.1,
                }}
              >
                {hero.name}
              </span>
              {generation > 1 && (
                <span
                  style={{
                    fontFamily: "var(--font-mono)",
                    fontSize: 10,
                    color: "var(--muted)",
                    letterSpacing: "0.06em",
                    textTransform: "uppercase",
                  }}
                  title="Поколение души (реинкарнация)"
                >
                  · пок. {generation}
                </span>
              )}
            </div>

            <div style={{ display: "flex", alignItems: "center", gap: 10, marginTop: 4, flexWrap: "wrap" }}>
              <span
                className="hero-sub"
                style={{
                  fontFamily: "var(--font-mono)",
                  fontSize: 11,
                  color: "var(--muted)",
                  letterSpacing: "0.04em",
                }}
              >
                {cap(hero.race)} · {cap(hero.hero_class)}
              </span>

              {/* Action Beacon Pill */}
              <span
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 5,
                  padding: "2px 8px",
                  borderRadius: "var(--radius-pill)",
                  background: `color-mix(in srgb, ${stateMeta.color} 14%, transparent)`,
                  border: `1px solid color-mix(in srgb, ${stateMeta.color} 40%, transparent)`,
                  fontSize: 10,
                  fontFamily: "var(--font-mono)",
                  fontWeight: 600,
                  color: stateMeta.color,
                }}
              >
                <span
                  className="beacon-pulse"
                  style={{
                    display: "inline-block",
                    width: 5,
                    height: 5,
                    borderRadius: "50%",
                    background: stateMeta.color,
                    color: stateMeta.color,
                  }}
                />
                <span>{stateMeta.icon} {stateMeta.label}</span>
              </span>
            </div>

            {bounty > 0 && (
              <span
                className="bounty-badge"
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 4,
                  marginTop: 4,
                  padding: "2px 8px",
                  borderRadius: "var(--radius-sm)",
                  background: "color-mix(in srgb, var(--danger) 15%, transparent)",
                  border: "1px solid color-mix(in srgb, var(--danger) 40%, transparent)",
                  color: "var(--danger)",
                  fontFamily: "var(--font-mono)",
                  fontSize: 10,
                  fontWeight: 600,
                }}
              >
                <Shield size={11} /> В розыске: {bounty} 🪙
              </span>
            )}
          </div>

          {/* Gold Coin Purse */}
          <div
            className="hero-gold shimmer-gold"
            title="Золото в кошеле героя"
            style={{
              padding: "6px 14px",
              background: "color-mix(in srgb, var(--gold) 14%, transparent)",
              border: "1px solid color-mix(in srgb, var(--gold) 45%, transparent)",
              borderRadius: "var(--radius-pill)",
              color: "var(--gold)",
              fontFamily: "var(--font-mono)",
              fontSize: 14,
              fontWeight: 700,
              display: "flex",
              alignItems: "center",
              gap: 6,
              boxShadow: "0 0 14px color-mix(in srgb, var(--gold) 20%, transparent)",
            }}
          >
            <span>{formatNumber(hero.gold)}</span>
            <span style={{ fontSize: 13 }}>🪙</span>
          </div>
        </div>

        {/* Vital Signs (HP, MP, SP, XP) */}
        <div className="hero-vitals" style={{ marginTop: 16 }}>
          <StatBar label="HP" value={hero.hp} max={hero.max_hp} color="hp" />
          <StatBar label="MP" value={hero.mp} max={hero.max_mp} color="mp" />
          <StatBar label="SP" value={hero.sp} max={hero.max_sp} color="sp" />
          <StatBar label="XP" value={hero.xp} max={hero.xp_to_next} color="xp" />
        </div>
      </div>
    </div>
  )
}

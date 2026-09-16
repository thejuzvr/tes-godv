import { useState } from "react"
import type { World } from "@/stores/gameStore"
import { api } from "@/lib/api"

const WEATHER_RU: Record<string, { label: string; icon: string }> = {
  clear: { label: "Ясно", icon: "☀️" },
  cloud: { label: "Облачно", icon: "☁️" },
  rain: { label: "Дождь", icon: "🌧️" },
  storm: { label: "Гроза", icon: "⛈️" },
  snow: { label: "Снег", icon: "❄️" },
}

const WEATHER_DESC: Record<string, string> = {
  rain: "клёв +30%, усталость быстрее",
  storm: "клёв +15%, уныние",
  snow: "голод быстрее",
  cloud: "пасмурно",
  clear: "хороший день",
}

const DONATE_PRESETS = [10, 50, 200]

const GATE_PRESETS = [50, 200]

// C-3: тип World.gates — summary из бекенда (public_snapshot)
type GatesSummary = {
  status: "closed" | "open"
  location_name: string | null
  fund: number
  target: number
  ticks_left: number | null
  top_donors: { hero_id: string; name: string; amount: number }[]
}

function GatesSection({ world, heroGold, onDonated }: { world: World; heroGold: number; onDonated: () => void }) {
  const g = (world as unknown as { gates?: GatesSummary }).gates
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)

  if (!g) return null

  const donate = async (amount: number) => {
    if (busy) return
    setBusy(true)
    setNotice(null)
    try {
      const res = await api.donateGates(amount)
      setNotice(res.closed ? "🌀 Врата запечатаны! Слава героям!" : `+${amount} золота в фонд — собрано ${res.gates.fund}`)
      onDonated()
    } catch (e: any) {
      const msg = e?.message || String(e)
      setNotice(
        msg.includes("not_enough_gold")
          ? "Не хватает золота."
          : msg.includes("gates_closed")
            ? "Врата схлопнулись раньше взноса — золото вернули."
            : "Взнос не принят, попробуй позже.",
      )
    } finally {
      setBusy(false)
    }
  }

  const fmt = (n: number) => n.toLocaleString("ru-RU")
  const progress = g.target > 0 ? Math.min(1, g.fund / g.target) : 0

  if (g.status !== "open") {
    return (
      <div style={{ marginTop: "var(--space-3)", fontSize: "var(--text-xs)", color: "var(--muted)" }}>
        🌀 Врата Обливиона запечатаны — в Скайриме тихо.
      </div>
    )
  }

  return (
    <div style={{ marginTop: "var(--space-3)", padding: "10px 12px", background: "color-mix(in oklab, var(--danger), transparent 92%)", border: "1px solid color-mix(in oklab, var(--danger), transparent 70%)", borderRadius: "var(--radius-md)" }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: 8, flexWrap: "wrap" }}>
        <span style={{ fontWeight: 600, fontSize: "var(--text-sm)" }}>🌀 Врата Обливиона</span>
        <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>над {g.location_name}</span>
        <span style={{ marginLeft: "auto", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--danger)" }}>
          {fmt(g.fund)} / {fmt(g.target)} 🪙
        </span>
      </div>

      <div
        style={{ marginTop: 8, height: 6, borderRadius: 3, background: "color-mix(in oklab, var(--fg), transparent 88%)", overflow: "hidden" }}
        role="progressbar"
        aria-valuenow={Math.round(progress * 100)}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label="Прогресс фонда экспедиции врат"
      >
        <div style={{ width: `${Math.round(progress * 100)}%`, height: "100%", background: "var(--danger)", transition: "width 0.4s" }} />
      </div>

      <div style={{ marginTop: 6, display: "flex", gap: 10, flexWrap: "wrap", fontSize: "var(--text-xs)", color: "var(--muted)" }}>
        <span>срок: {g.ticks_left ?? 0} тик(ов)</span>
        {g.top_donors.length > 0 && (
          <span>
            топ: {g.top_donors.map((d) => `${d.name} (${fmt(d.amount)})`).join(", ")}
          </span>
        )}
      </div>

      <div style={{ marginTop: 8, display: "flex", alignItems: "center", gap: 6, flexWrap: "wrap" }}>
        <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>В фонд экспедиции:</span>
        {GATE_PRESETS.map((amount) => (
          <button
            key={amount}
            disabled={busy || heroGold < amount}
            onClick={() => donate(amount)}
            aria-label={`Вложить ${amount} золота в фонд врат`}
            style={{
              padding: "3px 10px",
              fontSize: "var(--text-xs)",
              fontFamily: "var(--font-mono)",
              color: heroGold < amount ? "var(--muted)" : "var(--fg)",
              background: "transparent",
              border: "1px solid var(--border)",
              borderRadius: "var(--radius-sm)",
              cursor: busy || heroGold < amount ? "default" : "pointer",
              opacity: heroGold < amount ? 0.5 : 1,
              transition: "border-color 0.2s, color 0.2s",
            }}
          >
            {amount} 🪙
          </button>
        ))}
      </div>

      {notice && (
        <div role="status" aria-live="polite" style={{ marginTop: 6, fontSize: "var(--text-xs)", color: "var(--muted)" }}>
          {notice}
        </div>
      )}
    </div>
  )
}

function ConstructionSection({ world, heroGold, onDonated }: { world: World; heroGold: number; onDonated: () => void }) {
  const c = world.construction
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)

  if (!c) return null

  const donate = async (amount: number) => {
    if (busy) return
    setBusy(true)
    setNotice(null)
    try {
      const res = await api.donateConstruction(amount)
      setNotice(`+${amount} золота в фонд — собрано ${res.construction.collected}`)
      onDonated()
    } catch (e: any) {
      const msg = e?.message || String(e)
      setNotice(msg.includes("not_enough_gold") ? "Не хватает золота." : "Взнос не принят, попробуй позже.")
    } finally {
      setBusy(false)
    }
  }

  const fmt = (n: number) => n.toLocaleString("ru-RU")

  return (
    <div style={{ marginTop: "var(--space-3)", padding: "10px 12px", background: "var(--bg-elevated)", borderRadius: "var(--radius-md)" }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: 8, flexWrap: "wrap" }}>
        <span style={{ fontWeight: 600, fontSize: "var(--text-sm)" }}>🏗️ {c.project}</span>
        <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>
          этап {c.stage_index + 1}/{c.stages_total}: {c.stage}
        </span>
        <span style={{ marginLeft: "auto", fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--gold)" }}>
          {fmt(c.collected)} / {fmt(c.target)}
        </span>
      </div>

      <div style={{ marginTop: 8, height: 6, borderRadius: 3, background: "color-mix(in oklab, var(--fg), transparent 88%)", overflow: "hidden" }} role="progressbar" aria-valuenow={Math.round(c.progress * 100)} aria-valuemin={0} aria-valuemax={100} aria-label={`Прогресс стройки ${c.project}`}>
        <div style={{ width: `${Math.round(c.progress * 100)}%`, height: "100%", background: "var(--gold)", transition: "width 0.4s" }} />
      </div>

      <div style={{ marginTop: 8, display: "flex", alignItems: "center", gap: 6, flexWrap: "wrap" }}>
        <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>Пожертвовать:</span>
        {DONATE_PRESETS.map((amount) => (
          <button
            key={amount}
            disabled={busy || heroGold < amount}
            onClick={() => donate(amount)}
            aria-label={`Пожертвовать ${amount} золота на ${c.project}`}
            style={{
              padding: "3px 10px",
              fontSize: "var(--text-xs)",
              fontFamily: "var(--font-mono)",
              color: heroGold < amount ? "var(--muted)" : "var(--fg)",
              background: "transparent",
              border: "1px solid var(--border)",
              borderRadius: "var(--radius-sm)",
              cursor: busy || heroGold < amount ? "default" : "pointer",
              opacity: heroGold < amount ? 0.5 : 1,
              transition: "border-color 0.2s, color 0.2s",
            }}
          >
            {amount} 🪙
          </button>
        ))}
      </div>

      {notice && (
        <div role="status" aria-live="polite" style={{ marginTop: 6, fontSize: "var(--text-xs)", color: "var(--muted)" }}>
          {notice}
        </div>
      )}
    </div>
  )
}

export function WorldPanel({ world, heroRegion, heroGold = 0, onDonated }: { world: World | null; heroRegion?: string; heroGold?: number; onDonated?: () => void }) {
  if (!world) return null

  const weather = (heroRegion && world.weather?.[heroRegion]) || "clear"
  const w = WEATHER_RU[weather] || { label: weather, icon: "🌤️" }
  const events = world.events || []
  const wars = world.wars || []

  return (
    <div className="panel">
      <div className="panel-header">
        <div className="flex items-center gap-2">
          <span className="panel-icon">🌍</span>
          Мир
          <span style={{ marginLeft: "auto", fontSize: "var(--text-xs)", color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
            {world.season} · день {world.day}
          </span>
        </div>
      </div>
      <div className="panel-body">
        <div style={{ display: "flex", alignItems: "center", gap: "var(--space-3)", marginBottom: "var(--space-3)" }}>
          <span style={{ fontSize: 26 }}>{w.icon}</span>
          <div>
            <div style={{ fontWeight: 600 }}>{w.label}{heroRegion ? ` · ${heroRegion}` : ""}</div>
            <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>{WEATHER_DESC[weather]}</div>
          </div>
        </div>

        <ConstructionSection world={world} heroGold={heroGold} onDonated={onDonated || (() => {})} />

        <GatesSection world={world} heroGold={heroGold} onDonated={onDonated || (() => {})} />

        {wars.map((pair) => {
          const [a, b] = pair.split("|")
          return (
            <div key={pair} style={{ display: "flex", alignItems: "center", gap: 8, padding: "6px 10px", marginBottom: 6, background: "color-mix(in oklab, var(--danger), transparent 90%)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)" }}>
              <span>⚔️</span>
              <span><b>{a}</b> против <b>{b}</b> — войны не избежать. Цены в этих землях выросли.</span>
            </div>
          )
        })}

        {events.map((e) => (
          <div key={e.id} style={{ display: "flex", alignItems: "center", gap: 8, padding: "6px 10px", marginBottom: 6, background: "var(--bg-elevated)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)" }}>
            <span>{e.type === "fair" ? "🎪" : e.type === "dragon" ? "🐉" : e.type === "monster_wave" ? "👹" : e.type === "eclipse" ? "🌑" : e.type === "defection" ? "🔄" : e.type === "construction" ? "🏗️" : e.type === "oblivion_gate" ? "🌀" : e.type === "gate_closed" ? "✅" : e.type === "gate_fallen" ? "☠️" : "📜"}</span>
            <span style={{ flex: 1 }}>
              <b>{e.name}</b>
              {e.desc ? ` — ${e.desc}` : ""}
            </span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)" }}>{e.ttl}т</span>
          </div>
        ))}

        {events.length === 0 && wars.length === 0 && (
          <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)", textAlign: "center" }}>
            В Скайриме тихо... пока что.
          </div>
        )}
      </div>
    </div>
  )
}

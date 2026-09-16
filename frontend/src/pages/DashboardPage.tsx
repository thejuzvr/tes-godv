import { useEffect, useState, useCallback, useRef } from "react"
import { Link } from "react-router-dom"
import { Swords, Compass, Trophy, Skull, ChevronDown, BookOpen, Backpack, Globe, ArrowUpRight } from "lucide-react"
import "./dashboard-skin.css"
import { useGameStore } from "@/stores/gameStore"
import { api } from "@/lib/api"
import { formatNumber } from "@/lib/utils"
import { ObservatoryHeader } from "@/components/hero/ObservatoryHeader"
import { HeroActivityStrip } from "@/components/hero/HeroActivityStrip"
import { NeedsPanel } from "@/components/hero/NeedsPanel"
import { ReputationPanel } from "@/components/hero/ReputationPanel"
import { MoodPanel } from "@/components/hero/MoodPanel"
import { PetCard } from "@/components/hero/PetCard"
import { EquipmentPanel } from "@/components/hero/EquipmentPanel"
import { WorldPanel } from "@/components/hero/WorldPanel"
import { QuestPanel } from "@/components/game/QuestPanel"
import { InventoryPanel } from "@/components/game/InventoryPanel"
import { GodPanel } from "@/components/god/GodPanel"
import { JournalPanel } from "@/components/journal/JournalPanel"
import type { World } from "@/stores/gameStore"

interface CombatResult {
  monster_name?: string
  victory?: boolean
  hero_defeated?: boolean
  xp?: number
  gold?: number
  rounds?: number
  pet_death?: string
}

/* P-2: оверлей смерти с таймером возрождения (данные — только из state_data.death) */
function DeathOverlay({ stateData }: { stateData?: string }) {
  const death = (() => {
    try {
      const sd = stateData ? JSON.parse(stateData) : {}
      return sd?.death?.respawn_at ? sd.death : null
    } catch { return null }
  })()

  const [, forceTick] = useState(0)
  useEffect(() => {
    if (!death) return
    const id = setInterval(() => forceTick((n) => n + 1), 1000)
    return () => clearInterval(id)
  }, [death])

  if (!death) return null

  // грабля TZ: respawn_at — naive UTC с бекенда, парсим с "Z"
  const leftMs = new Date(death.respawn_at + "Z").getTime() - Date.now()
  const leftSec = Math.max(0, Math.ceil(leftMs / 1000))
  const mm = Math.floor(leftSec / 60)
  const ss = leftSec % 60
  const timer = `${String(mm).padStart(2, "0")}:${String(ss).padStart(2, "0")}`

  return (
    <div className="panel" role="status" style={{ borderColor: "var(--danger)", background: "color-mix(in oklab, var(--danger), transparent 92%)" }}>
      <div className="panel-header" style={{ color: "var(--danger)" }}>
        <div className="flex items-center gap-2"><span className="panel-icon">💀</span> Герой пал{death.city_name ? ` · возвращение в ${death.city_name}` : ""}</div>
      </div>
      <div className="panel-body">
        <div style={{ display: "flex", gap: "var(--space-4)", alignItems: "center", flexWrap: "wrap" }}>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-lg)", fontWeight: 700 }}>
            {leftMs <= 0 ? "возвращается…" : timer}
          </span>
          <span style={{ fontSize: "var(--text-sm)", color: "var(--muted)" }}>
            Смерть — не конец: −10% золота, при пробуждении 20% здоровья и новое поколение души.
          </span>
        </div>
      </div>
    </div>
  )
}

/* ─── Main Dashboard — обсерватория: герой / хроника / воля бога ─── */
export function DashboardPage({ onWs }: { onWs?: (type: string, handler: (data: any) => void) => () => void }) {
  const { hero, journal, journalCount, setHero, setJournal, setJournalCount, addJournalEntry, setWorld, world } = useGameStore()
  const [loading, setLoading] = useState(true)
  const [equipRefresh, setEquipRefresh] = useState(0)
  const [invRefresh, setInvRefresh] = useState(0)
  const [questRefresh, setQuestRefresh] = useState(0)
  const [repRefresh, setRepRefresh] = useState(0)
  const [combatResult, setCombatResult] = useState<CombatResult | null>(null)
  const [arsenalTab, setArsenalTab] = useState<"equipment" | "inventory">("equipment")
  const resultTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const fetchData = useCallback(async () => {
    try {
      const [h, j, c] = await Promise.all([api.getHero(), api.getJournal(50), api.getJournalCount()])
      setHero(h); setJournal(j); setJournalCount(c.count)
      // W-7: снапшот мира (WS-толчок + резервный поллинг)
      try {
        const w = await api.getWorld()
        if (w?.snapshot) setWorld(w.snapshot as World)
      } catch {}
    } catch (e) { console.error(e) }
    finally { setLoading(false) }
  }, [setHero, setJournal, setJournalCount, setWorld])

  // Initial fetch + fallback polling every 60 seconds
  useEffect(() => { fetchData(); const id = setInterval(fetchData, 60000); return () => clearInterval(id) }, [fetchData])

  // Ручные действия с предметами (надеть/снять) — событие от InventoryPanel
  useEffect(() => {
    const handler = () => { fetchData(); setEquipRefresh((p) => p + 1) }
    window.addEventListener("tes:hero-refresh", handler)
    return () => window.removeEventListener("tes:hero-refresh", handler)
  }, [fetchData])

  // WebSocket real-time updates
  const heroRef = useRef(hero)
  heroRef.current = hero

  useEffect(() => {
    if (!onWs) return
    const unsubs = [
      onWs("journal_entry", (msg) => {
        if (msg.data) {
          addJournalEntry(msg.data)
        }
      }),
      onWs("hero_update", (msg) => {
        if (msg.data && heroRef.current) {
          setHero({ ...heroRef.current, ...msg.data })
          setInvRefresh(prev => prev + 1)
          setQuestRefresh(prev => prev + 1)
          setRepRefresh(prev => prev + 1)
        }
      }),
      onWs("combat_progress", (msg) => {
        if (msg.data && heroRef.current) {
          try {
            const sd = JSON.parse(heroRef.current.state_data || "{}")
            sd.combat = { ...sd.combat, ...msg.data }
            setHero({ ...heroRef.current, state_data: JSON.stringify(sd) })
          } catch {}
        }
      }),
      onWs("combat_start", (msg) => {
        if (msg.data && heroRef.current) {
          try {
            const sd = JSON.parse(heroRef.current.state_data || "{}")
            sd.combat = msg.data
            setHero({ ...heroRef.current, state: "fighting", state_data: JSON.stringify(sd) })
          } catch {}
        }
      }),
      onWs("combat_result", (msg) => {
        if (!msg.data) return
        setCombatResult(msg.data as CombatResult)
        if (resultTimer.current) clearTimeout(resultTimer.current)
        resultTimer.current = setTimeout(() => setCombatResult(null), 12000)
      }),
      onWs("equipment_update", () => {
        setEquipRefresh(prev => prev + 1)
        setInvRefresh(prev => prev + 1)
      }),
      // W-7: снапшот ядра мира (погода/цены/события/войны)
      onWs("world_update", (msg) => {
        if (msg.data?.snapshot) setWorld(msg.data.snapshot as World)
      }),
    ]
    return () => unsubs.forEach(u => u())
  }, [onWs, addJournalEntry, setHero, setWorld])

  const handleGod = async (type: string) => {
    try {
      const res = await api.godAction(type)
      const [heroData, j, c] = await Promise.all([api.getHero(), api.getJournal(50), api.getJournalCount()])
      setHero(heroData)
      setJournal(j)
      setJournalCount(c.count)
      return res?.narrative || null
    } catch (e) { console.error(e); throw e }
  }

  useEffect(() => () => { if (resultTimer.current) clearTimeout(resultTimer.current) }, [])

  if (loading || !hero) return <div className="dashboard"><div style={{ textAlign: "center", color: "var(--muted)", padding: 48 }}>Загрузка…</div></div>

  return (
    <>
      <ObservatoryHeader hero={hero} />
      <HeroActivityStrip hero={hero} />

      {/* Combat result banner (WS combat_result) */}
      {combatResult && (
        <div
          className="panel combat-result-banner stone-card"
          role="status"
          aria-live="polite"
          style={{
            border: `1px solid ${combatResult.victory ? "var(--gold)" : "var(--danger)"}`,
            boxShadow: `0 0 20px color-mix(in srgb, ${combatResult.victory ? "var(--gold)" : "var(--danger)"} 25%, transparent)`,
            marginBottom: "var(--space-3)",
          }}
        >
          <div className="panel-body" style={{ padding: "10px 18px", display: "flex", alignItems: "center", gap: 14 }}>
            <span style={{ fontSize: 20 }}>
              {combatResult.victory ? <Trophy size={20} color="var(--gold)" /> : combatResult.hero_defeated ? <Skull size={20} color="var(--danger)" /> : "🕊️"}
            </span>
            <span style={{ fontSize: 14, fontWeight: 700, fontFamily: "var(--font-display)", fontStyle: "italic" }}>
              {combatResult.victory
                ? `Победа над ${combatResult.monster_name || "врагом"}!`
                : combatResult.hero_defeated
                ? `${hero.name} пал в бою от руки ${combatResult.monster_name || "врага"}`
                : `${combatResult.monster_name || "Враг"} отступил — бой окончен`}
            </span>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--accent)", marginLeft: "auto" }}>
              {combatResult.victory && `+${combatResult.xp || 0} XP · +${formatNumber(combatResult.gold || 0)} 🪙`}
              {combatResult.pet_death && ` · ${combatResult.pet_death}`}
            </span>
          </div>
        </div>
      )}

      {/* Unified Banners: Travel + Combat (Combat Duel Arena) */}
      {(() => {
        try {
          const state = JSON.parse(hero.state_data || "{}")
          const travel = state.travel
          const combat = state.combat
          const isTraveling = travel && (hero.state === "traveling" || travel.ticks_left > 0)
          const isFighting = combat && (hero.state === "fighting" || combat.rounds_left > 0)

          // Combat Arena Banner
          if (isFighting) {
            const heroPct = combat.hero_max_hp > 0 ? Math.min(100, (combat.hero_hp / combat.hero_max_hp) * 100) : 0
            const monsterPct = combat.monster_max_hp > 0 ? Math.min(100, (combat.monster_hp / combat.monster_max_hp) * 100) : 0
            const currentRound = combat.round || (20 - (combat.rounds_left || 0))

            return (
              <div
                className="panel combat-arena fantasy-window parchment-glow"
                style={{
                  marginBottom: "var(--space-3)",
                }}
              >
                <div className="panel-body" style={{ padding: "14px 20px" }}>
                  {/* Top Bar of Combat Arena */}
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
                    <span
                      style={{
                        display: "inline-flex",
                        alignItems: "center",
                        gap: 6,
                        fontFamily: "var(--font-mono)",
                        fontSize: 11,
                        textTransform: "uppercase",
                        letterSpacing: "0.1em",
                        color: "var(--danger)",
                        fontWeight: 700,
                      }}
                    >
                      <Swords size={14} /> Битва насмерть
                      {isTraveling && <span style={{ color: "var(--muted)" }}>· в пути к {travel.destination_name}</span>}
                    </span>
                    <span
                      style={{
                        padding: "2px 10px",
                        borderRadius: "var(--radius-pill)",
                        background: "color-mix(in srgb, var(--danger) 15%, transparent)",
                        border: "1px solid color-mix(in srgb, var(--danger) 35%, transparent)",
                        fontFamily: "var(--font-mono)",
                        fontSize: 11,
                        color: "var(--danger)",
                      }}
                    >
                      Раунд {currentRound} / {combat.max_rounds || 20}
                    </span>
                  </div>

                  {/* Duel Arena Fighters Grid */}
                  <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
                    {/* Hero Side */}
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 4 }}>
                        <span style={{ fontFamily: "var(--font-display)", fontSize: 16, fontStyle: "italic", fontWeight: 700, color: "var(--fg)" }}>
                          🛡️ {hero.name}
                        </span>
                        <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, fontWeight: 700, color: "var(--hp)" }}>
                          {combat.hero_hp} / {combat.hero_max_hp}
                        </span>
                      </div>
                      <div style={{ height: 10, background: "color-mix(in srgb, var(--bg) 90%, black)", borderRadius: "var(--radius-pill)", overflow: "hidden" }}>
                        <div
                          style={{
                            height: "100%",
                            width: `${heroPct}%`,
                            background: "linear-gradient(90deg, #920703, var(--hp))",
                            boxShadow: "0 0 10px var(--hp)",
                            borderRadius: "var(--radius-pill)",
                            transition: "width 0.4s ease",
                          }}
                        />
                      </div>
                    </div>

                    {/* VS Badge */}
                    <div
                      className="anim-duel-vs"
                      style={{
                        width: 42,
                        height: 42,
                        borderRadius: "50%",
                        background: "radial-gradient(circle, color-mix(in srgb, var(--danger) 45%, black), black)",
                        border: "2px solid var(--danger)",
                        boxShadow: "0 0 18px color-mix(in srgb, var(--danger) 60%, transparent)",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        fontFamily: "var(--font-display)",
                        fontWeight: 800,
                        fontSize: 14,
                        color: "#fff",
                        textShadow: "0 0 8px var(--danger)",
                        flexShrink: 0,
                      }}
                    >
                      VS
                    </div>

                    {/* Monster Side */}
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", marginBottom: 4 }}>
                        <span style={{ fontFamily: "var(--font-display)", fontSize: 16, fontStyle: "italic", fontWeight: 700, color: "var(--fg)" }}>
                          {combat.monster_icon || "👹"} {combat.monster_name}
                        </span>
                        <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, fontWeight: 700, color: "var(--danger)" }}>
                          {combat.monster_hp} / {combat.monster_max_hp}
                        </span>
                      </div>
                      <div style={{ height: 10, background: "color-mix(in srgb, var(--bg) 90%, black)", borderRadius: "var(--radius-pill)", overflow: "hidden" }}>
                        <div
                          style={{
                            height: "100%",
                            width: `${monsterPct}%`,
                            background: "linear-gradient(90deg, #920703, #c0392b)",
                            boxShadow: "0 0 10px #c0392b",
                            borderRadius: "var(--radius-pill)",
                            transition: "width 0.4s ease",
                          }}
                        />
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            )
          }

          // Travel-only banner
          if (isTraveling) {
            const pct = ((travel.total_ticks - travel.ticks_left) / travel.total_ticks) * 100
            const hoursLeft = travel.ticks_left * 0.25
            const timeText = hoursLeft >= 1
              ? `${Math.round(hoursLeft)} ч ${Math.round((hoursLeft % 1) * 60)} мин`
              : `${Math.round(hoursLeft * 60)} мин`

            return (
              <div
                className="panel travel-banner stone-card parchment-glow"
                style={{
                  border: "1px solid color-mix(in srgb, var(--accent) 45%, var(--border))",
                  marginBottom: "var(--space-3)",
                }}
              >
                <div className="panel-body" style={{ padding: "12px 18px" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
                    <div
                      style={{
                        width: 32,
                        height: 32,
                        borderRadius: "var(--radius-sm)",
                        background: "color-mix(in srgb, var(--accent) 15%, transparent)",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        color: "var(--accent)",
                        flexShrink: 0,
                      }}
                    >
                      <Compass size={18} />
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 6 }}>
                        <span style={{ fontSize: 14, fontWeight: 700, fontFamily: "var(--font-display)", fontStyle: "italic" }}>
                          Переход в {travel.destination_name}
                        </span>
                        <span style={{ fontSize: 11, color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
                          Осталось ~{timeText} ({travel.ticks_left} тиков)
                        </span>
                      </div>
                      <div style={{ height: 6, background: "color-mix(in srgb, var(--bg) 90%, black)", borderRadius: "var(--radius-pill)", overflow: "hidden" }}>
                        <div
                          style={{
                            height: "100%",
                            width: `${pct}%`,
                            background: "var(--accent)",
                            boxShadow: "0 0 10px var(--accent)",
                            borderRadius: "var(--radius-pill)",
                            transition: "width 0.5s ease",
                          }}
                        />
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            )
          }
        } catch { return null }
      })()}

      {/* P-3: решётка камеры — визуальный оверлей поверх всего дашборда */}
      {hero.state === "jailed" && <div className="jail-bars-overlay" aria-hidden="true" data-testid="jail-bars" />}

      {/* P-2: Death overlay — герой мёртв, таймер до возрождения в ближайшем городе */}
      {hero.state === "dead" && <DeathOverlay stateData={hero.state_data ?? undefined} />}

      {/* Jail overlay: герой в тюрьме */}
      {hero.state === "jailed" && (() => {
        try {
          const sd = hero.state_data ? JSON.parse(hero.state_data) : {}
          const jail = sd.jail
          if (!jail) return null
          return (
            <div className="panel" style={{ borderColor: "var(--warn)", background: "color-mix(in oklab, var(--warn), transparent 92%)" }}>
              <div className="panel-header" style={{ color: "var(--warn)" }}>
                <div className="flex items-center gap-2"><span className="panel-icon">⛓️</span> В тюрьме{jail.location_name ? ` · ${jail.location_name}` : ""}</div>
              </div>
              <div className="panel-body">
                <div style={{ display: "flex", gap: "var(--space-4)", alignItems: "center", flexWrap: "wrap" }}>
                  <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-lg)", fontWeight: 700 }}>
                    {jail.ticks_left} / {jail.total_ticks} тиков
                  </span>
                  <span style={{ fontSize: "var(--text-sm)", color: "var(--muted)" }}>
                    Причина: {jail.reason === "steal" ? "кража" : jail.reason === "break_in" ? "проникновение" : "проступок"}
                    {jail.mode === "bribe" && " · решает откупиться"}
                    {jail.mode === "escape" && " · готовит побег"}
                    {jail.mode === "serve" && " · отсиживается"}
                  </span>
                  <span style={{ fontSize: "var(--text-sm)", color: "var(--muted)", marginLeft: "auto", fontFamily: "var(--font-mono)" }}>
                    Награда при аресте: {jail.bounty_at_arrest} 💰
                  </span>
                </div>
              </div>
            </div>
          )
        } catch { return null }
      })()}

      <div className="observatory-workspace">
        <section className="observatory-story" aria-label="Приключение героя">
          <div className="observatory-section-heading"><span><BookOpen size={17} aria-hidden="true"/> История продолжается</span><Link to="/narratives">Мастерская <ArrowUpRight size={14} aria-hidden="true"/></Link></div>
          <QuestPanel refreshTrigger={questRefresh} />
          <JournalPanel entries={journal} count={journalCount} />
        </section>
        <aside className="observatory-sidebar" aria-label="Вмешательство и состояние">
          <GodPanel onAction={handleGod} hero={hero} />
          <details className="observatory-dossier">
            <summary><span><Backpack size={18} aria-hidden="true"/> Досье героя<small>Снаряжение, потребности и спутник</small></span><ChevronDown size={18} aria-hidden="true"/></summary>
            <div className="observatory-dossier-content">
          <NeedsPanel hero={hero} />
          <MoodPanel mood={hero.mood} moodHistory={hero.mood_history || []} />
          <PetCard pets={hero.pets} />

          {/* Объединённый Арсенал героя: Снаряжение / Сумка */}
          <div className="panel fantasy-window arsenal-module">
            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                padding: "8px 12px",
                borderBottom: "1px solid var(--border)",
                background: "color-mix(in srgb, var(--surface-raised) 85%, black)",
              }}
            >
              <div style={{ display: "flex", gap: 6 }}>
                <button
                  type="button"
                  onClick={() => setArsenalTab("equipment")}
                  style={{
                    padding: "4px 12px",
                    borderRadius: "var(--radius-pill)",
                    fontSize: "var(--text-xs)",
                    fontFamily: "var(--font-mono)",
                    fontWeight: 600,
                    border: "1px solid",
                    borderColor: arsenalTab === "equipment" ? "var(--accent)" : "transparent",
                    background: arsenalTab === "equipment" ? "var(--accent)" : "transparent",
                    color: arsenalTab === "equipment" ? "var(--accent-on)" : "var(--muted)",
                    cursor: "pointer",
                    transition: "all 150ms ease",
                  }}
                >
                  ⚔️ Снаряжение
                </button>
                <button
                  type="button"
                  onClick={() => setArsenalTab("inventory")}
                  style={{
                    padding: "4px 12px",
                    borderRadius: "var(--radius-pill)",
                    fontSize: "var(--text-xs)",
                    fontFamily: "var(--font-mono)",
                    fontWeight: 600,
                    border: "1px solid",
                    borderColor: arsenalTab === "inventory" ? "var(--accent)" : "transparent",
                    background: arsenalTab === "inventory" ? "var(--accent)" : "transparent",
                    color: arsenalTab === "inventory" ? "var(--accent-on)" : "var(--muted)",
                    cursor: "pointer",
                    transition: "all 150ms ease",
                  }}
                >
                  🎒 Сумка
                </button>
              </div>
              <span style={{ fontSize: 10, fontFamily: "var(--font-mono)", color: "var(--muted)" }}>
                {arsenalTab === "equipment" ? "6 слотов" : "16 ячеек"}
              </span>
            </div>

            {arsenalTab === "equipment" ? (
              <EquipmentPanel refreshTrigger={equipRefresh} headless />
            ) : (
              <InventoryPanel refreshTrigger={invRefresh} headless />
            )}
          </div>

          <ReputationPanel refreshTrigger={repRefresh} />
            </div>
          </details>
          <details className="observatory-dossier observatory-world" open>
            <summary><span><Globe size={18} aria-hidden="true"/> За пределами хроники<small>События и общие дела Скайрима</small></span><ChevronDown size={18} aria-hidden="true"/></summary>
            <div className="observatory-dossier-content"><WorldPanel world={world} heroRegion={hero.location?.region} heroGold={hero.gold} onDonated={fetchData} /></div>
          </details>
        </aside>
      </div>
    </>
  )
}

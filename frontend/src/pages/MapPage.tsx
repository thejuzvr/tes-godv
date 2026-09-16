import { useCallback, useEffect, useRef, useState } from "react"
import { Link } from "react-router-dom"
import { useGameStore } from "@/stores/gameStore"
import { api } from "@/lib/api"
import { WorldMap, dangerColor, TYPE_RU, WEATHER_RU } from "@/components/map/WorldMap"
import type { MapLocation } from "@/components/map/WorldMap"
import type { World } from "@/stores/gameStore"

const PRICE_RU: Record<string, string> = {
  food: "Провизия", gear: "Снаряжение", rare: "Редкое", lodging: "Ночлег",
}

const FLAG_RU: Record<string, { icon: string; label: string }> = {
  water: { icon: "🎣", label: "Рыбалка" },
  gather_nodes: { icon: "🌿", label: "Сбор трав" },
  locked_buildings: { icon: "🚪", label: "Взлом" },
}

const busyKeys = ["fighting", "traveling", "jailed", "fishing", "gathering", "stealing", "breaking_in"]

/* ─── Карта мира (M-3b): полноэкранная страница.
   Канвас карты занимает всю рабочую область; досье локации, войны и события —
   плавающие оверлеи поверх карты. Путь героя — пилюля снизу. ─── */
export function MapPage({ onWs }: { onWs?: (type: string, handler: (data: any) => void) => () => void }) {
  const { hero, setHero, world, setWorld } = useGameStore()
  const [locations, setLocations] = useState<MapLocation[] | null>(null)
  const [failed, setFailed] = useState(false)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)
  const [dossierOpen, setDossierOpen] = useState(true)

  const fetchData = useCallback(async () => {
    try {
      const [locs, w, h] = await Promise.all([api.getLocations(), api.getWorld(), api.getHero()])
      setLocations(locs as MapLocation[])
      if (w?.snapshot) setWorld(w.snapshot as World)
      if (h) setHero(h)
      setFailed(false)
    } catch (e) {
      console.error(e)
      setFailed(true)
    }
  }, [setHero, setWorld])

  useEffect(() => {
    fetchData()
    const id = setInterval(fetchData, 60000)
    return () => clearInterval(id)
  }, [fetchData])

  // WS-живость: герой и мир обновляются так же, как на дашборде
  const heroRef = useRef(hero)
  heroRef.current = hero
  useEffect(() => {
    if (!onWs) return
    const unsubs = [
      onWs("hero_update", (msg: any) => {
        if (msg.data && heroRef.current) setHero({ ...heroRef.current, ...msg.data })
      }),
      onWs("world_update", (msg: any) => {
        if (msg.data?.snapshot) setWorld(msg.data.snapshot as World)
      }),
    ]
    return () => unsubs.forEach((u) => u())
  }, [onWs, setHero, setWorld])

  // Выбор по умолчанию — локация героя
  useEffect(() => {
    if (!selectedId && hero?.location?.id) setSelectedId(hero.location.id)
  }, [hero?.location?.id, selectedId])

  const heroSd = (() => {
    try { return JSON.parse(hero?.state_data || "{}") } catch { return {} }
  })()
  const travel = heroSd.travel
  const isTraveling = !!travel && (hero?.state === "traveling" || travel.ticks_left > 0)
  const heroBusy = !!hero?.state && busyKeys.includes(hero.state)
  const heroLocId = hero?.location?.id || null
  const travelDestId = isTraveling ? travel.destination_id || null : null

  const selected = locations?.find((l) => l.id === selectedId) || null

  const go = async (loc: MapLocation) => {
    if (busy || heroBusy) return
    setBusy(true)
    setNotice(null)
    try {
      const res = await api.travel(loc.id)
      setNotice(res?.message?.replace(/^Traveling to\s+/, "В путь: ") || `В путь: ${loc.name}`)
      const h = await api.getHero()
      setHero(h)
      setDossierOpen(true)
    } catch (e: any) {
      setNotice(e?.message || "Не получилось отправиться в путь")
    } finally {
      setBusy(false)
    }
  }

  const regionWeather = selected ? world?.weather?.[selected.region] : null
  const selWeather = regionWeather ? (WEATHER_RU[regionWeather] || { label: regionWeather, icon: "🌤️", desc: "" }) : null
  const heroRegionWeather = (hero?.location?.region && world?.weather?.[hero.location.region]) || "clear"
  const heroW = WEATHER_RU[heroRegionWeather] || { label: heroRegionWeather, icon: "🌤️", desc: "" }

  return (
    <div className="map-stage">
      {/* Канвас: карта занимает всю рабочую область */}
      {locations === null ? (
        <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", color: "var(--muted)" }}>
          {failed ? "Карта недоступна — сервер не отвечает. Обнови страницу." : "Прорисовка карты…"}
        </div>
      ) : (
        <WorldMap
          locations={locations}
          selectedId={selectedId}
          onSelect={setSelectedId}
          heroLocId={heroLocId}
          travelDestId={travelDestId}
          world={world}
        />
      )}

      {/* Верхний левый чип: атлас · календарь · погода региона героя */}
      <div className="map-overlay map-title-chip">
        <span className="map-title">Карта мира</span>
        <span className="map-meta">
          {world ? `${world.season} · день ${world.day}` : "календарь загружается…"}
          {hero?.location?.region ? ` · ${heroW.icon} ${heroW.label} · ${hero.location.region}` : ""}
        </span>
        {heroLocId && <Link to="/" style={{ fontSize: "var(--text-xs)", color: "var(--accent)", textDecoration: "none" }}>← Панель</Link>}
      </div>

      {/* Пилюля пути */}
      {isTraveling && (
        <div className="map-overlay map-travel-pill" role="status" aria-live="polite">
          🚶 Путь к {travel.destination_name} · ~{travel.ticks_left} тик{travel.ticks_left === 1 ? "" : "ов"}
        </div>
      )}

      {/* Досье локации + мир + события: плавающий оверлей справа */}
      {dossierOpen ? (
        <aside className="map-overlay map-dossier" aria-label="Досье локации">
          <button className="map-dossier-toggle" onClick={() => setDossierOpen(false)} aria-expanded="true" aria-label="Свернуть досье">
            ▸ Досье локации — свернуть
          </button>

          {/* Локация */}
          <section className="map-dossier-section">
            {!selected ? (
              <div style={{ fontSize: "var(--text-sm)", color: "var(--muted)" }}>
                Выбери станцию на карте — здесь появится её досье.
              </div>
            ) : (
              <>
                <div style={{ display: "flex", alignItems: "baseline", gap: "var(--space-2)", flexWrap: "wrap" }}>
                  <span style={{ fontFamily: "var(--font-display)", fontSize: "var(--text-xl)", fontWeight: 700 }}>{selected.name}</span>
                  {selected.id === heroLocId && (
                    <span style={{ fontSize: "var(--text-xs)", color: "var(--success)", fontFamily: "var(--font-mono)" }}>★ герой здесь</span>
                  )}
                </div>
                <div style={{ display: "flex", gap: "var(--space-2)", margin: "var(--space-2) 0", flexWrap: "wrap" }}>
                  <span style={chip}>{TYPE_RU[selected.location_type] || selected.location_type}</span>
                  <span style={{ ...chip, color: dangerColor(selected.danger_level), borderColor: dangerColor(selected.danger_level) }}>
                    ⚠ {selected.danger_level}
                  </span>
                  <span style={{ ...chip, fontFamily: "var(--font-mono)" }}>ур. {selected.min_level}–{selected.max_level}</span>
                </div>
                {selected.description && (
                  <p style={{ fontSize: "var(--text-sm)", color: "var(--muted)", margin: 0 }}>{selected.description}</p>
                )}
                <div style={{ display: "flex", gap: "var(--space-3)", marginTop: "var(--space-2)", fontSize: "var(--text-xs)", flexWrap: "wrap" }}>
                  <span>{selected.has_shop ? "🏪 Магазин" : <span style={{ color: "var(--muted)" }}>🏪 Нет лавки</span>}</span>
                  <span>{selected.has_inn ? "🍺 Таверна" : <span style={{ color: "var(--muted)" }}>🍺 Нет ночлега</span>}</span>
                </div>
                {Object.keys(selected.flags || {}).length > 0 && (
                  <div style={{ display: "flex", gap: "var(--space-2)", marginTop: "var(--space-2)", flexWrap: "wrap" }}>
                    {Object.keys(selected.flags).filter((f) => FLAG_RU[f]).map((f) => (
                      <span key={f} style={chip}>{FLAG_RU[f].icon} {FLAG_RU[f].label}</span>
                    ))}
                  </div>
                )}

                {/* Путь — бывшая TravelPanel (P-2b → M-3) */}
                <div style={{ marginTop: "var(--space-3)" }}>
                  {selected.id === heroLocId ? (
                    <div style={{ fontSize: "var(--text-xs)", color: "var(--success)", fontFamily: "var(--font-mono)" }}>Герой уже здесь</div>
                  ) : (
                    <button
                      onClick={() => go(selected)}
                      disabled={heroBusy || busy}
                      aria-label={`Идти в ${selected.name}`}
                      style={{
                        width: "100%", padding: "8px 12px", fontWeight: 600, fontSize: "var(--text-sm)",
                        border: "1px solid var(--accent)", borderRadius: "var(--radius-sm)",
                        background: "transparent", color: "var(--accent)",
                        cursor: heroBusy || busy ? "wait" : "pointer",
                        opacity: heroBusy || busy ? 0.4 : 1,
                        transition: "opacity 0.2s",
                        touchAction: "manipulation",
                      }}
                    >
                      Идти в {selected.name}
                    </button>
                  )}
                  {heroBusy && selected.id !== heroLocId && (
                    <div style={{ fontSize: "var(--text-xs)", color: "var(--warn)", marginTop: "var(--space-1)" }}>
                      Герой занят{isTraveling ? " — в пути" : ""}.
                    </div>
                  )}
                  {notice && (
                    <div role="status" style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--success)", marginTop: "var(--space-2)" }}>
                      {notice}
                    </div>
                  )}
                </div>
              </>
            )}
          </section>

          {/* Мир здесь */}
          <section className="map-dossier-section">
            <div style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", letterSpacing: "0.05em", color: "var(--muted)", marginBottom: "var(--space-2)" }}>
              🌍 Мир здесь
            </div>
            {selected ? (
              <>
                <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", marginBottom: "var(--space-2)" }}>
                  <span style={{ fontSize: 22 }}>{selWeather?.icon || "🌤️"}</span>
                  <div>
                    <div style={{ fontWeight: 600, fontSize: "var(--text-sm)" }}>{selWeather?.label || "Погода неизвестна"}</div>
                    <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>
                      {selWeather?.desc || selected.region}
                    </div>
                  </div>
                </div>
                {world?.density?.[selected.id] != null && (
                  <div style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", marginBottom: "var(--space-2)" }}>
                    Столкновения ×{Number(world.density[selected.id]).toFixed(2)}
                  </div>
                )}
                {selected.location_type === "city" && world?.prices?.[selected.id] && (
                  <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "var(--space-1) var(--space-3)" }}>
                    {Object.entries(world.prices[selected.id]).map(([cat, mult]) => (
                      <div key={cat} style={{ display: "flex", justifyContent: "space-between", fontSize: "var(--text-xs)" }}>
                        <span style={{ color: "var(--muted)" }}>{PRICE_RU[cat] || cat}</span>
                        <span style={{ fontFamily: "var(--font-mono)", fontVariantNumeric: "tabular-nums" }}>
                          ×{Number(mult).toFixed(2)}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </>
            ) : (
              <div style={{ fontSize: "var(--text-sm)", color: "var(--muted)" }}>Выбери локацию на карте.</div>
            )}
          </section>

          {/* Войны и события */}
          <section className="map-dossier-section">
            <div style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", textTransform: "uppercase", letterSpacing: "0.05em", color: "var(--muted)", marginBottom: "var(--space-2)" }}>
              ⚔️ Войны и события
            </div>
            {(world?.wars?.length ?? 0) === 0 && (world?.events?.length ?? 0) === 0 ? (
              <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)", textAlign: "center" }}>
                Тишина. Ни войн, ни событий.
              </div>
            ) : (
              <>
                {(world?.wars || []).map((pair) => {
                  const [a, b] = pair.split("|")
                  return (
                    <div key={pair} style={{ display: "flex", alignItems: "center", gap: 8, padding: "6px 10px", marginBottom: 6, background: "color-mix(in oklab, var(--danger), transparent 90%)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)" }}>
                      <span>⚔️</span>
                      <span><b>{a}</b> против <b>{b}</b></span>
                    </div>
                  )
                })}
                {(world?.events || []).map((e) => (
                  <div key={e.id} style={{ display: "flex", alignItems: "center", gap: 8, padding: "6px 10px", marginBottom: 6, background: "var(--bg-elevated)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)" }}>
                    <span>{e.type === "fair" ? "🎪" : e.type === "dragon" ? "🐉" : e.type === "monster_wave" ? "👹" : e.type === "eclipse" ? "🌑" : e.type === "defection" ? "🔄" : "📜"}</span>
                    <span style={{ flex: 1 }}><b>{e.name}</b>{e.desc ? ` — ${e.desc}` : ""}</span>
                    <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)" }}>{e.ttl}т</span>
                  </div>
                ))}
              </>
            )}
          </section>
        </aside>
      ) : (
        <div className="map-overlay map-dossier-collapsed">
          <button className="map-dossier-toggle" onClick={() => setDossierOpen(true)} aria-expanded="false" aria-label="Развернуть досье">
            ◂ Досье{selected ? ` · ${selected.name}` : ""}
          </button>
        </div>
      )}
    </div>
  )
}

const chip: React.CSSProperties = {
  fontSize: "var(--text-xs)",
  padding: "2px 8px",
  borderRadius: "999px",
  border: "1px solid var(--border)",
  color: "var(--muted)",
  background: "var(--bg-elevated)",
  whiteSpace: "nowrap",
}

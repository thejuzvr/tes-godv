import { useCallback, useEffect, useRef, useState } from "react"
import { Link } from "react-router-dom"
import { ArrowLeft, ArrowRight, Check, ChevronDown, ChevronUp, Cloud, CloudLightning, CloudRain, Compass, DoorOpen, Fish, Flag, Footprints, Leaf, MapPin, Moon, RefreshCw, ScrollText, ShieldAlert, Snowflake, Sparkles, Store, Sun, Swords, Tent, TriangleAlert, Users, Wine } from "lucide-react"
import type { LucideIcon } from "lucide-react"
import { useGameStore } from "@/stores/gameStore"
import { api } from "@/lib/api"
import { WorldMap, TYPE_RU, WEATHER_RU } from "@/components/map/WorldMap"
import type { MapLocation } from "@/components/map/WorldMap"
import type { World } from "@/stores/gameStore"
import "./map-dossier.css"

const PRICE_RU: Record<string, string> = {
  food: "Провизия", gear: "Снаряжение", rare: "Редкое", lodging: "Ночлег",
}
const FLAG_RU: Record<string, { icon: LucideIcon; label: string }> = {
  water: { icon: Fish, label: "Рыбалка" },
  gather_nodes: { icon: Leaf, label: "Сбор трав" },
  locked_buildings: { icon: DoorOpen, label: "Взлом" },
}
const WEATHER_ICONS: Record<string, LucideIcon> = { clear: Sun, cloud: Cloud, rain: CloudRain, storm: CloudLightning, snow: Snowflake }
const EVENT_ICONS: Record<string, LucideIcon> = { fair: Tent, dragon: ShieldAlert, monster_wave: Swords, eclipse: Moon, defection: Flag }
const busyKeys = ["fighting", "traveling", "jailed", "fishing", "gathering", "stealing", "breaking_in"]

export function MapPage({ onWs }: { onWs?: (type: string, handler: (data: any) => void) => () => void }) {
  const { hero, setHero, world, setWorld } = useGameStore()
  const [locations, setLocations] = useState<MapLocation[] | null>(null)
  const [failed, setFailed] = useState(false)
  const [loading, setLoading] = useState(false)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState<{ kind: "success" | "error"; text: string } | null>(null)
  const [dossierOpen, setDossierOpen] = useState(true)

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const [locs, w, h] = await Promise.all([api.getLocations(), api.getWorld(), api.getHero()])
      setLocations(locs as MapLocation[])
      if (w?.snapshot) setWorld(w.snapshot as World)
      if (h) setHero(h)
      setFailed(false)
    } catch (e) {
      console.error(e)
      setFailed(true)
    } finally {
      setLoading(false)
    }
  }, [setHero, setWorld])

  useEffect(() => {
    fetchData()
    const id = setInterval(fetchData, 60000)
    return () => clearInterval(id)
  }, [fetchData])

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

  const selectLocation = (id: string) => {
    setSelectedId(id)
    setDossierOpen(true)
    setNotice(null)
  }
  const go = async (loc: MapLocation) => {
    if (busy || heroBusy) return
    setBusy(true)
    setNotice(null)
    try {
      const res = await api.travel(loc.id)
      setNotice({ kind: "success", text: res?.message?.replace(/^Traveling to\s+/, "В путь: ") || `В путь: ${loc.name}` })
      setDossierOpen(true)
      try {
        const h = await api.getHero()
        setHero(h)
      } catch {
        setNotice({ kind: "error", text: "Путешествие начато, но статус героя не обновился. Обновите данные карты." })
        setFailed(true)
      }
    } catch (e: any) {
      setNotice({ kind: "error", text: e?.message || "Не получилось отправиться в путь. Попробуйте ещё раз." })
    } finally {
      setBusy(false)
    }
  }

  const regionWeather = selected ? world?.weather?.[selected.region] : null
  const selWeather = regionWeather ? (WEATHER_RU[regionWeather] || { label: regionWeather, desc: "" }) : null
  const heroRegionWeather = (hero?.location?.region && world?.weather?.[hero.location.region]) || "clear"
  const heroW = WEATHER_RU[heroRegionWeather] || { label: heroRegionWeather }
  const HeroWeatherIcon = WEATHER_ICONS[heroRegionWeather] || Cloud
  const WeatherIcon = WEATHER_ICONS[regionWeather || ""] || Cloud

  return (
    <div className="map-stage">
      {locations === null ? (
        <div className="map-frame">
          <div className="map-load-state" role={failed ? "alert" : "status"}>
            <Compass size={36} aria-hidden="true" />
            <h2>{failed ? "Карта недоступна" : "Загружаем атлас…"}</h2>
            <p>{failed ? "Не удалось получить данные мира. Проверьте соединение и повторите попытку." : "Локации, погода и события Скайрима."}</p>
            {failed && <button className="map-retry" onClick={fetchData} disabled={loading}><RefreshCw size={15} aria-hidden="true" />{loading ? "Обновляем…" : "Повторить загрузку"}</button>}
          </div>
        </div>
      ) : (
        <WorldMap locations={locations} selectedId={selectedId} onSelect={selectLocation} heroLocId={heroLocId} travelDestId={travelDestId} world={world} />
      )}

      <header className="map-overlay map-title-chip">
        <div className="atlas-title-row">
          <Compass className="atlas-title-mark" size={32} aria-hidden="true" />
          <div><span className="atlas-eyebrow">Атлас провинции</span><h1 className="map-title">Скайрим</h1></div>
          <Link className="atlas-back" to="/" aria-label="Вернуться на панель героя"><ArrowLeft size={15} aria-hidden="true" /><span>К герою</span></Link>
        </div>
        <div className="map-meta">
          <span>{world ? `${world.season} · день ${world.day}` : "Календарь загружается…"}</span>
          {hero?.location?.region && <span><HeroWeatherIcon size={13} aria-hidden="true" />{heroW.label} · {hero.location.region}</span>}
        </div>
      </header>

      {isTraveling && <div className="map-overlay map-travel-pill" role="status"><Footprints size={17} aria-hidden="true" /><span>Путь к <b>{travel.destination_name}</b> · ~{travel.ticks_left} тик{travel.ticks_left === 1 ? "" : "ов"}</span></div>}

      <aside className={`map-overlay map-dossier${dossierOpen ? "" : " map-dossier-collapsed"}`} aria-label="Досье локации">
        <button className="map-dossier-toggle" onClick={() => setDossierOpen(!dossierOpen)} aria-expanded={dossierOpen} aria-controls="map-dossier-content">
          <span><MapPin size={15} aria-hidden="true" />Досье локации</span>
          {dossierOpen ? <ChevronUp size={17} aria-hidden="true" /> : <ChevronDown size={17} aria-hidden="true" />}
        </button>
        <div id="map-dossier-content" hidden={!dossierOpen}>
          <div className="atlas-location-picker">
            <label htmlFor="atlas-location">Выбрать локацию</label>
            <select id="atlas-location" value={selected?.id || ""} onChange={(e) => selectLocation(e.target.value)} disabled={!locations?.length}>
              <option value="" disabled>{locations === null ? "Загрузка локаций…" : "Все локации Скайрима"}</option>
              {(locations || []).map((loc) => <option key={loc.id} value={loc.id}>{loc.name} · {loc.region}</option>)}
            </select>
          </div>
          {failed && locations !== null && <div className="atlas-notice" data-kind="error" role="alert"><TriangleAlert size={16} aria-hidden="true" /><div>Данные не обновились. Показана последняя версия.<button className="map-retry" onClick={fetchData} disabled={loading}><RefreshCw size={14} aria-hidden="true" />{loading ? "Обновляем…" : "Обновить данные"}</button></div></div>}

          <section className="map-dossier-section atlas-location">
            {!selected ? <div className="atlas-empty"><MapPin size={26} aria-hidden="true" /><p>Выберите точку на карте или локацию из списка — здесь появятся условия и маршрут.</p></div> : <>
              <p className="atlas-eyebrow">{selected.region}</p>
              <h2 className="atlas-location-name">{selected.name}</h2>
              {selected.id === heroLocId && <p className="atlas-here"><MapPin size={13} aria-hidden="true" />Герой здесь</p>}
              <div className="atlas-tags">
                <span>{TYPE_RU[selected.location_type] || selected.location_type}</span>
                <span className="atlas-danger" data-danger={selected.danger_level}><ShieldAlert size={13} aria-hidden="true" />{selected.danger_level}</span>
                <span>ур. {selected.min_level}–{selected.max_level}</span>
              </div>
              {selected.description && <p className="atlas-description">{selected.description}</p>}
              <div className="atlas-amenities">
                <span data-available={selected.has_shop}><Store size={15} aria-hidden="true" />{selected.has_shop ? "Магазин" : "Нет лавки"}</span>
                <span data-available={selected.has_inn}><Wine size={15} aria-hidden="true" />{selected.has_inn ? "Таверна" : "Нет ночлега"}</span>
              </div>
              <div className="atlas-activities">
                {Object.keys(selected.flags || {}).filter((f) => FLAG_RU[f]).map((f) => { const Icon = FLAG_RU[f].icon; return <span key={f}><Icon size={14} aria-hidden="true" />{FLAG_RU[f].label}</span> })}
              </div>
              <div className="atlas-travel-action">
                {selected.id === heroLocId ? <div className="atlas-current"><Check size={16} aria-hidden="true" />Герой уже здесь</div> : <>
                  <button className="atlas-travel-button" onClick={() => go(selected)} disabled={heroBusy || busy || !hero} aria-describedby={heroBusy ? "atlas-travel-reason" : undefined}>
                    <Footprints size={19} aria-hidden="true" /><span>{busy ? "Отправляемся…" : `Идти в ${selected.name}`}</span><ArrowRight size={17} aria-hidden="true" />
                  </button>
                  {heroBusy && <p className="atlas-travel-reason" id="atlas-travel-reason">{isTraveling ? "Герой в пути. Новый маршрут можно выбрать после прибытия." : "Герой занят. Отправиться можно после завершения действия."}</p>}
                  {!hero && <p className="atlas-travel-reason">Для путешествия нужен герой.</p>}
                </>}
              </div>
            </>}
            {notice && <div className="atlas-notice" data-kind={notice.kind} role={notice.kind === "error" ? "alert" : "status"}>{notice.kind === "error" ? <TriangleAlert size={16} aria-hidden="true" /> : <Check size={16} aria-hidden="true" />}<span>{notice.text}</span></div>}
          </section>

          <section className="map-dossier-section">
            <h3 className="atlas-section-heading"><Cloud size={15} aria-hidden="true" />Погода и условия</h3>
            {selected ? <>
              <div className="atlas-weather"><WeatherIcon size={30} strokeWidth={1.4} aria-hidden="true" /><div><strong>{selWeather?.label || "Погода неизвестна"}</strong><p>{selWeather?.desc || selected.region}</p></div></div>
              {world?.density?.[selected.id] != null && <div className="atlas-density"><Users size={14} aria-hidden="true" /><span>Столкновения</span><b>×{Number(world.density[selected.id]).toFixed(2)}</b></div>}
              {selected.location_type === "city" && world?.prices?.[selected.id] && <div className="atlas-prices"><h4>Цены в городе</h4><dl>{Object.entries(world.prices[selected.id]).map(([cat, mult]) => <div key={cat}><dt>{PRICE_RU[cat] || cat}</dt><dd>×{Number(mult).toFixed(2)}</dd></div>)}</dl></div>}
            </> : <p className="atlas-muted">Выберите локацию, чтобы узнать условия региона.</p>}
          </section>

          <section className="map-dossier-section">
            <h3 className="atlas-section-heading"><ScrollText size={15} aria-hidden="true" />Войны и события<span className="atlas-event-count">{(world?.wars?.length || 0) + (world?.events?.length || 0)}</span></h3>
            {!world ? <p className="atlas-muted">Сведения о мире загружаются…</p> : (world.wars?.length ?? 0) === 0 && (world.events?.length ?? 0) === 0 ? <div className="atlas-peace"><Sparkles size={18} aria-hidden="true" /><p>В провинции спокойно.<br /><span>Сейчас нет войн и событий.</span></p></div> : <div className="atlas-events">
              {(world?.wars || []).map((pair) => { const [a, b] = pair.split("|"); return <div key={pair} className="atlas-event atlas-war"><Swords size={17} aria-hidden="true" /><p><b>{a}</b> против <b>{b}</b></p></div> })}
              {(world?.events || []).map((e) => { const Icon = EVENT_ICONS[e.type] || ScrollText; return <div key={e.id} className="atlas-event"><Icon size={17} aria-hidden="true" /><p><b>{e.name}</b>{e.desc && <span>{e.desc}</span>}</p><span className="atlas-event-ttl" title="Осталось тиков">{e.ttl} т.</span></div> })}
            </div>}
          </section>
        </div>
      </aside>
    </div>
  )
}

import { useEffect, useRef, useState } from "react"
import type { World } from "@/stores/gameStore"

/* ─── Карта мира (M-3/M-3c): интерактивная SVG-карта Скайрима.
   Сигнатура «карта-звёздный атлас»: узлы-станции по геометрии типа локации
   (город = двойное кольцо, деревня = круг, дичь = треугольник, подземелье = ромб),
   герой — пульсирующая звезда, маршрут в пути — пунктирный кометный след.
   M-3c: зум колесом/кнопками, пан перетаскиванием, центрирование на герое,
   легенда, каскадное появление узлов. Координаты узлов — данные из БД. ─── */

export interface MapLocation {
  id: string
  name: string
  description: string
  region: string
  location_type: string
  danger_level: string
  min_level: number
  max_level: number
  has_shop: boolean
  has_inn: boolean
  map_x: number | null
  map_y: number | null
  flags: Record<string, any>
}

export const TYPE_RU: Record<string, string> = {
  village: "Деревня", city: "Город", town: "Поселение", camp: "Лагерь",
  ruin: "Руины", cave: "Пещера", dungeon: "Подземелье", wilderness: "Дикая местность",
}

export const WEATHER_RU: Record<string, { label: string; icon: string; desc: string }> = {
  clear: { label: "Ясно", icon: "☀️", desc: "хороший день" },
  cloud: { label: "Облачно", icon: "☁️", desc: "пасмурно" },
  rain: { label: "Дождь", icon: "🌧️", desc: "клёв +30%, усталость быстрее" },
  storm: { label: "Гроза", icon: "⛈️", desc: "клёв +15%, уныние" },
  snow: { label: "Снег", icon: "❄️", desc: "голод быстрее" },
}

const DANGER_COLOR: Record<string, string> = {
  "Низкая": "var(--success)",
  "Средняя": "var(--gold)",
  "Высокая": "var(--warn)",
  "Экстремальная": "var(--danger)",
}

export function dangerColor(level: string): string {
  return DANGER_COLOR[level] || "var(--muted)"
}

/* ─── Вид карты: k=зум, x/y=сдвиг в координатах viewBox ─── */
const VIEW_W = 1000
const VIEW_H = 700
const MIN_K = 1
const MAX_K = 4

/* P-1: подложка-артвор Skyrim.svg (31000×31000, квадрат) поверх фона, под данными.
   Калибровка — точная проекция провинции (границы холдов X 1782..29098,
   Y 8911..29185 → 943×700 на канвасе, поля 28.5). Узлы (map_x/map_y в reseed)
   синхронизированы с этой проекцией: города сидят на своих иконках артворка. */
const SUBSTRATE = { x: -33, y: -308, w: 1070, h: 1070 }
const SUBSTRATE_KEY = "tes:map-substrate"

const clampView = (v: { k: number; x: number; y: number }) => ({
  k: Math.min(MAX_K, Math.max(MIN_K, v.k)),
  // карта не должна уехать за края: при k=1 сдвиг нулевой
  x: Math.min(0, Math.max(VIEW_W * (1 - v.k), v.k === 1 ? 0 : v.x)),
  y: Math.min(0, Math.max(VIEW_H * (1 - v.k), v.k === 1 ? 0 : v.y)),
})

function NodeShape({ loc }: { loc: MapLocation }) {
  const stroke = dangerColor(loc.danger_level)
  const common = { fill: "var(--surface)", strokeWidth: 2, style: { stroke } }
  switch (loc.location_type) {
    case "city":
      return (
        <g className="node-body">
          <circle r={13} className="node-ring" {...common} />
          <circle r={5.5} {...common} strokeWidth={1.5} />
        </g>
      )
    case "village":
      return (
        <g className="node-body">
          <circle r={9} className="node-ring" {...common} />
          <circle r={2.5} style={{ fill: stroke }} />
        </g>
      )
    case "dungeon":
      return (
        <g className="node-body">
          <rect x={-9.5} y={-9.5} width={19} height={19} rx={3} transform="rotate(45)" className="node-ring" {...common} />
          <circle r={3} style={{ fill: stroke }} />
        </g>
      )
    default: // wilderness и прочее — треугольник
      return (
        <g className="node-body">
          <path d="M 0 -11 L 10.5 8 L -10.5 8 Z" className="node-ring" {...common} strokeLinejoin="round" />
          <circle r={2.5} cy={2} style={{ fill: stroke }} />
        </g>
      )
  }
}

function CompassRose() {
  return (
    <g transform="translate(940 64)" opacity={0.6}>
      <circle r={22} fill="none" stroke="var(--muted)" strokeWidth={1} />
      <path d="M 0 -18 L 4 0 L 0 18 L -4 0 Z" fill="var(--muted)" />
      <path d="M -18 0 L 0 -4 L 18 0 L 0 4 Z" fill="none" stroke="var(--muted)" strokeWidth={1} />
      <text y={-28} textAnchor="middle" className="map-terrain-label">С</text>
    </g>
  )
}

/* Декоративная хроматика карты: море, река, горы — тише всех данных */
function Terrain() {
  return (
    <g aria-hidden="true">
      <path d="M 0 300 C 130 280, 230 190, 300 30 L 0 0 Z" className="map-terrain-fill" />
      <path d="M 0 300 C 130 280, 230 190, 300 30" className="map-terrain" />
      <text x={100} y={140} className="map-terrain-label">Море Призраков</text>
      <path d="M 645 470 C 620 520, 580 540, 545 570 C 570 610, 640 640, 700 665" className="map-terrain" />
      <text x={648} y={588} className="map-terrain-label" transform="rotate(24 648 588)">Белая река</text>
      <g className="map-terrain" aria-hidden="true">
        <path d="M 596 416 l 12 -20 l 12 20" />
        <path d="M 616 424 l 14 -24 l 14 24" />
        <path d="M 640 416 l 11 -18 l 11 18" />
      </g>
    </g>
  )
}

interface WorldMapProps {
  locations: MapLocation[]
  selectedId: string | null
  onSelect: (id: string) => void
  heroLocId: string | null
  travelDestId: string | null
  world: World | null
}

export function WorldMap({ locations, selectedId, onSelect, heroLocId, travelDestId, world }: WorldMapProps) {
  const placed = locations.filter((l) => l.map_x != null && l.map_y != null)
  const heroLoc = placed.find((l) => l.id === heroLocId) || null
  const destLoc = placed.find((l) => l.id === travelDestId) || null

  const [view, setView] = useState({ k: 1, x: 0, y: 0 })
  const [substrate, setSubstrate] = useState(() => localStorage.getItem(SUBSTRATE_KEY) !== "off")
  const svgRef = useRef<SVGSVGElement | null>(null)
  const dragRef = useRef<{ startX: number; startY: number; baseX: number; baseY: number } | null>(null)
  const movedRef = useRef(false)
  // узел, на котором начался pointerdown: выбор делаем на pointerup,
  // т.к. setPointerCapture уводит click-событие на корень svg (клик по узлу «пропадает»)
  const pendingSelectRef = useRef<string | null>(null)

  const clampViewSafe = (v: { k: number; x: number; y: number }) => setView(clampView(v))

  // колесо мыши: зум к курсору (непассивный листенер — preventDefault)
  useEffect(() => {
    const svg = svgRef.current
    if (!svg) return
    const onWheel = (e: WheelEvent) => {
      e.preventDefault()
      const rect = svg.getBoundingClientRect()
      // точка курсора в координатах viewBox
      const px = ((e.clientX - rect.left) / rect.width) * VIEW_W
      const py = ((e.clientY - rect.top) / rect.height) * VIEW_H
      setView((v) => {
        const factor = e.deltaY < 0 ? 1.18 : 1 / 1.18
        const k = Math.min(MAX_K, Math.max(MIN_K, v.k * factor))
        const ratio = k / v.k
        return clampView({ k, x: px - (px - v.x) * ratio, y: py - (py - v.y) * ratio })
      })
    }
    svg.addEventListener("wheel", onWheel, { passive: false })
    return () => svg.removeEventListener("wheel", onWheel)
  }, [])

  const screenToView = (clientX: number, clientY: number) => {
    const rect = svgRef.current!.getBoundingClientRect()
    // preserveAspectRatio="xMidYMid meet" по умолчанию: контент леттербоксится внутри
    // элемента — реальный масштаб = min(w/W, h/H), плюс центрирующий сдвиг
    const scale = Math.min(rect.width / VIEW_W, rect.height / VIEW_H)
    const offX = (rect.width - VIEW_W * scale) / 2
    const offY = (rect.height - VIEW_H * scale) / 2
    return { px: (clientX - rect.left - offX) / scale, py: (clientY - rect.top - offY) / scale }
  }

  const onPointerDown = (e: React.PointerEvent) => {
    if (e.button !== 0) return
    // P-1: запрет нативного выделения/перетаскивания при пан-драге
    e.preventDefault()
    const { px, py } = screenToView(e.clientX, e.clientY)
    dragRef.current = { startX: px, startY: py, baseX: view.x, baseY: view.y }
    movedRef.current = false
    const nodeEl = (e.target as Element).closest?.(".map-node")
    pendingSelectRef.current = nodeEl?.getAttribute("data-loc-id") || null
    try { svgRef.current?.setPointerCapture(e.pointerId) } catch { /* синтетика/отпущенный указатель */ }
  }
  const onPointerMove = (e: React.PointerEvent) => {
    const d = dragRef.current
    if (!d) return
    const { px, py } = screenToView(e.clientX, e.clientY)
    const dx = px - d.startX
    const dy = py - d.startY
    if (Math.abs(dx) > 5 || Math.abs(dy) > 5) movedRef.current = true
    if (movedRef.current) clampViewSafe({ k: view.k, x: d.baseX + dx, y: d.baseY + dy })
  }
  const onPointerUp = (e: React.PointerEvent) => {
    // короткое нажатие без сдвига = выбор локации (см. pendingSelectRef)
    if (!movedRef.current && pendingSelectRef.current) onSelect(pendingSelectRef.current)
    pendingSelectRef.current = null
    dragRef.current = null
    try { svgRef.current?.releasePointerCapture?.(e.pointerId) } catch { /* нет активного указателя */ }
  }

  const zoomBy = (factor: number) => {
    setView((v) => {
      const k = Math.min(MAX_K, Math.max(MIN_K, v.k * factor))
      const ratio = k / v.k
      const cx = VIEW_W / 2
      const cy = VIEW_H / 2
      return clampView({ k, x: cx - (cx - v.x) * ratio, y: cy - (cy - v.y) * ratio })
    })
  }

  const centerOnHero = () => {
    if (!heroLoc) return
    setView((v) => {
      const k = v.k > 1.6 ? v.k : 2.2
      return clampView({ k, x: VIEW_W / 2 - heroLoc.map_x! * k, y: VIEW_H / 2 - heroLoc.map_y! * k })
    })
  }

  const onKeyDown = (e: React.KeyboardEvent, id: string) => {
    if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onSelect(id) }
  }

  return (
    <div className="map-frame">
      <svg
        ref={svgRef}
        viewBox={`0 0 ${VIEW_W} ${VIEW_H}`}
        className="map-canvas"
        role="group"
        aria-label="Карта Скайрима: локации, герой и путь"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerLeave={onPointerUp}
      >
        {/* канвас карты сливается с фоном страницы */}
        <rect x={0} y={0} width={VIEW_W} height={VIEW_H} fill="var(--bg)" />

        {/* весь контент — в трансформ-группе вида (зум/пан) */}
        <g transform={`translate(${view.x} ${view.y}) scale(${view.k})`}>
          {/* P-1: артвор Skyrim.svg — подложка под данными (pointer-events нет) */}
          {substrate && (
            <image
              href="/skyrim.svg"
              x={SUBSTRATE.x}
              y={SUBSTRATE.y}
              width={SUBSTRATE.w}
              height={SUBSTRATE.h}
              className="map-substrate"
              data-muted="true"
              aria-hidden="true"
              preserveAspectRatio="xMidYMid meet"
            />
          )}

          <g className="map-graticule" aria-hidden="true">
            {[100, 200, 300, 400, 500, 600, 700, 800, 900].map((x) => (
              <line key={`v${x}`} x1={x} y1={0} x2={x} y2={VIEW_H} />
            ))}
            {[100, 200, 300, 400, 500, 600].map((y) => (
              <line key={`h${y}`} x1={0} y1={y} x2={VIEW_W} y2={y} />
            ))}
          </g>

          <Terrain />
          <CompassRose />

          {/* кометный след маршрута в пути */}
          {heroLoc && destLoc && destLoc.id !== heroLoc.id && (
            <g aria-hidden="true">
              <path
                d={`M ${heroLoc.map_x} ${heroLoc.map_y} Q ${(heroLoc.map_x! + destLoc.map_x!) / 2} ${(heroLoc.map_y! + destLoc.map_y!) / 2 - 46} ${destLoc.map_x} ${destLoc.map_y}`}
                className="map-route"
                fill="none"
                stroke="var(--accent)"
                strokeWidth={2}
              />
              <circle cx={destLoc.map_x!} cy={destLoc.map_y!} r={17} fill="none" stroke="var(--accent)" strokeWidth={1.5} strokeDasharray="3 4" />
            </g>
          )}

          {/* узлы-локации с каскадным появлением */}
          {placed.map((loc, idx) => {
            const selected = loc.id === selectedId
            const isHero = loc.id === heroLocId
            return (
              <g
                key={loc.id}
                className="map-node"
                data-selected={selected}
                data-loc-id={loc.id}
                role="button"
                tabIndex={0}
                aria-label={`${loc.name}, ${TYPE_RU[loc.location_type] || loc.location_type}, опасность: ${loc.danger_level}${isHero ? ", герой здесь" : ""}`}
                onKeyDown={(e) => onKeyDown(e, loc.id)}
                style={{ animationDelay: `${Math.min(idx * 60, 480)}ms` }}
              >
                {selected && (
                  <circle cx={loc.map_x!} cy={loc.map_y!} r={19} fill="none" stroke="var(--accent)" strokeWidth={2} strokeDasharray="2 3" />
                )}
                {/* прозрачная hit-зона: весь узел кликабелен, не только контур */}
                <circle cx={loc.map_x!} cy={loc.map_y!} r={24} fill="transparent" stroke="none" />
                <g transform={`translate(${loc.map_x} ${loc.map_y})`}>
                  <NodeShape loc={loc} />
                </g>
                {loc.has_shop && (
                  <text x={loc.map_x! + 15} y={loc.map_y! - 6} className="map-node-badge">🏪</text>
                )}
                {loc.has_inn && (
                  <text x={loc.map_x! + 15} y={loc.map_y! + 8} className="map-node-badge">🍺</text>
                )}
                <text x={loc.map_x!} y={loc.map_y! + 34} textAnchor="middle" className="map-node-label">
                  {loc.name}
                </text>
                <text x={loc.map_x!} y={loc.map_y! + 48} textAnchor="middle" className="map-node-sub">
                  ур. {loc.min_level}–{loc.max_level}{world?.weather?.[loc.region] ? ` · ${WEATHER_RU[world.weather[loc.region]]?.icon || ""}` : ""}
                </text>
              </g>
            )
          })}

          {/* герой — пульсирующая звезда поверх узла */}
          {heroLoc && (
            <g transform={`translate(${heroLoc.map_x} ${heroLoc.map_y})`} aria-label="Позиция героя">
              <circle r={10} className="map-hero-pulse" fill="var(--accent)" opacity={0.5} />
              <path d="M 0 -7 L 2 -2 L 7 0 L 2 2 L 0 7 L -2 2 L -7 0 L -2 -2 Z" fill="var(--accent)" stroke="var(--bg)" strokeWidth={1.5} />
            </g>
          )}
        </g>
      </svg>

      {/* Легенда: геометрия типов + цвета опасности */}
      <div className="map-overlay map-legend" aria-label="Легенда карты">
        <div className="map-legend-row">
          <svg viewBox="-14 -14 28 28" width={16} height={16} aria-hidden="true"><circle r={11} fill="none" stroke="var(--muted)" strokeWidth={2} /><circle r={4.5} fill="none" stroke="var(--muted)" strokeWidth={1.5} /></svg>
          <span>Город</span>
          <svg viewBox="-14 -14 28 28" width={16} height={16} aria-hidden="true"><circle r={9} fill="none" stroke="var(--muted)" strokeWidth={2} /></svg>
          <span>Деревня</span>
          <svg viewBox="-14 -14 28 28" width={16} height={16} aria-hidden="true"><path d="M 0 -10 L 9.5 7 L -9.5 7 Z" fill="none" stroke="var(--muted)" strokeWidth={2} strokeLinejoin="round" /></svg>
          <span>Дичь</span>
          <svg viewBox="-14 -14 28 28" width={16} height={16} aria-hidden="true"><rect x={-8} y={-8} width={16} height={16} rx={2.5} transform="rotate(45)" fill="none" stroke="var(--muted)" strokeWidth={2} /></svg>
          <span>Подземелье</span>
        </div>
        <div className="map-legend-row">
          {Object.entries(DANGER_COLOR).map(([level, color]) => (
            <span key={level} className="map-legend-danger">
              <i style={{ background: color }} />
              {level}
            </span>
          ))}
        </div>
      </div>

      {/* Управление видом: зум ±, центр на герое, сброс */}
      <div className="map-zoom-cluster" role="group" aria-label="Управление видом карты">
        <button className="map-zoom-btn" onClick={() => zoomBy(1.3)} aria-label="Приблизить" title="Приблизить">＋</button>
        <button className="map-zoom-btn" onClick={() => zoomBy(1 / 1.3)} aria-label="Отдалить" title="Отдалить">－</button>
        <button className="map-zoom-btn" onClick={centerOnHero} aria-label="Центрировать на герое" title="Центр на герое" disabled={!heroLoc}>⌖</button>
        <button className="map-zoom-btn" onClick={() => clampViewSafe({ k: 1, x: 0, y: 0 })} aria-label="Сбросить вид" title="Вся карта">⟲</button>
        <button
          className="map-zoom-btn map-substrate-toggle"
          data-on={substrate}
          onClick={() => setSubstrate((on) => { localStorage.setItem(SUBSTRATE_KEY, on ? "off" : "on"); return !on })}
          aria-label="Подложка артвор" aria-pressed={substrate}
          title={substrate ? "Скрыть подложку-артвор" : "Показать подложку-артвор"}
        >🗺️</button>
        <span className="map-zoom-scale" aria-hidden="true">×{view.k.toFixed(1)}</span>
      </div>
    </div>
  )
}

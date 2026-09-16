import { useState, useEffect } from "react"
import { useSearchParams } from "react-router-dom"
import { Crown, Swords, Coins, Hourglass, RefreshCw, Trophy, Shield, AlertCircle } from "lucide-react"
import { api } from "@/lib/api"
import { formatNumber, formatTime } from "@/lib/utils"
import "./pantheon-observatory.css"

interface PantheonEntry {
  rank: number
  hero_name: string
  hero_level: number
  value: number
}
type Metric = "kills" | "gold" | "time"
const metricConfig = {
  kills: { label: "Убийства", heading: "Имена, закалённые битвой", unit: "убийств", icon: Swords, api: () => api.getPantheonKills(), format: (v: number) => formatNumber(v) },
  gold: { label: "Богатство", heading: "Состояния, ставшие легендой", unit: "золота", icon: Coins, api: () => api.getPantheonGold(), format: (v: number) => formatNumber(v) },
  time: { label: "Время в мире", heading: "Долгий путь оставляет след", unit: "в мире", icon: Hourglass, api: () => api.getPantheonTime(), format: (v: number) => formatTime(v) },
}

export function PantheonPage() {
  const [params, setParams] = useSearchParams()
  const rawMetric = params.get("metric")
  const metric: Metric = rawMetric === "gold" || rawMetric === "time" ? rawMetric : "kills"
  const [result, setResult] = useState<{ metric: Metric; entries: PantheonEntry[] } | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)
  const [revision, setRevision] = useState(0)
  const [updatedAt, setUpdatedAt] = useState<Date | null>(null)

  useEffect(() => {
    let active = true
    let pending = false
    setError(false)
    const load = async () => {
      if (pending) return
      pending = true
      setLoading(true)
      try {
        const entries = await metricConfig[metric].api()
        if (active) {
          setResult({ metric, entries })
          setUpdatedAt(new Date())
          setError(false)
        }
      } catch { if (active) setError(true) }
      finally { pending = false; if (active) setLoading(false) }
    }
    void load()
    const timer = setInterval(load, 30000)
    return () => { active = false; clearInterval(timer) }
  }, [metric, revision])

  const data = result?.metric === metric ? result.entries : []
  const leaders = data.filter((entry) => entry.rank >= 1 && entry.rank <= 3).sort((a, b) => a.rank - b.rank)
  const rest = data.filter((entry) => entry.rank > 3).sort((a, b) => a.rank - b.rank)
  const config = metricConfig[metric]
  const MetricIcon = config.icon

  return (
    <main className="pantheon-observatory">
      <header className="pantheon-intro">
        <div className="pantheon-intro-copy">
          <span className="pantheon-eyebrow"><Crown size={16} aria-hidden="true"/> Зал славы Тамриэля</span>
          <h1>Пантеон</h1>
          <p>Одни оставляют след клинком. Другие — целым состоянием.<br/>Здесь история помнит каждого по его свершениям.</p>
        </div>
        <div className="pantheon-emblem" aria-hidden="true"><span/><Crown size={54} strokeWidth={1}/><span/></div>
      </header>

      <div className="pantheon-toolbar">
        <div className="pantheon-metrics" role="group" aria-label="Показатель рейтинга">
          {(Object.keys(metricConfig) as Metric[]).map((key) => {
            const Icon = metricConfig[key].icon
            return <button key={key} aria-pressed={metric === key} onClick={() => { const next = new URLSearchParams(params); next.set("metric", key); setParams(next, { replace: true }) }}><Icon size={17} aria-hidden="true"/>{metricConfig[key].label}</button>
          })}
        </div>
        <button className="pantheon-refresh" onClick={() => setRevision((n) => n + 1)} disabled={loading}><RefreshCw size={15} aria-hidden="true"/>{loading ? "Обновляем…" : "Обновить"}</button>
      </div>

      {error && <div className="pantheon-notice" role="alert"><AlertCircle size={18} aria-hidden="true"/><span>Не удалось обновить рейтинг.{data.length ? " Показаны последние полученные данные." : " Проверьте соединение и нажмите «Обновить»."}</span></div>}

      <section className="pantheon-ranking" aria-labelledby="pantheon-ranking-title" aria-busy={loading}>
        <div className="pantheon-section-title"><h2 id="pantheon-ranking-title">{config.heading}</h2><span>{data.length ? `${data.length} в рейтинге` : "Рейтинг героев"}</span></div>
        {loading && !data.length ? <div className="pantheon-empty" role="status"><Hourglass size={30} aria-hidden="true"/><h3>Собираем имена героев…</h3><p>Сведения о свершениях загружаются.</p></div> : !data.length ? <div className="pantheon-empty"><Trophy size={32} aria-hidden="true"/><h3>{error ? "Летопись пока недоступна" : "Легенды ещё впереди"}</h3><p>{error ? "Попробуйте обновить рейтинг ещё раз." : "В этой категории пока нет записей. Герои продолжают свой путь."}</p></div> : <>
          {leaders.length > 0 && <ol className="pantheon-leaders" aria-label="Лидеры рейтинга">
            {leaders.map((entry) => <li key={entry.rank} className="pantheon-leader" data-rank={entry.rank} value={entry.rank}>
              <div className="pantheon-leader-top"><span className="pantheon-place">{entry.rank === 1 ? <Crown size={17} aria-hidden="true"/> : <Shield size={16} aria-hidden="true"/>} {entry.rank} место</span><span className="pantheon-level">Уровень {entry.hero_level}</span></div>
              <div className="pantheon-monogram" aria-hidden="true">{entry.hero_name.charAt(0).toUpperCase()}</div>
              <h3>{entry.hero_name}</h3>
              <div className="pantheon-achievement"><MetricIcon size={17} aria-hidden="true"/><strong>{config.format(entry.value)}</strong><span>{config.unit}</span></div>
            </li>)}
          </ol>}
          {rest.length > 0 && <div className="pantheon-table-wrap" role="region" aria-label="Таблица рейтинга" tabIndex={0}><table className="pantheon-table"><caption>Остальные участники · {config.label.toLowerCase()}</caption><thead><tr><th scope="col">Место</th><th scope="col">Герой</th><th scope="col">Уровень</th><th scope="col">{config.label}</th></tr></thead><tbody>{rest.map((entry) => <tr key={entry.rank}><td className="pantheon-table-rank">{entry.rank}</td><th scope="row"><span className="pantheon-row-seal" aria-hidden="true">{entry.hero_name.charAt(0).toUpperCase()}</span>{entry.hero_name}</th><td>{entry.hero_level}</td><td>{config.format(entry.value)}</td></tr>)}</tbody></table></div>}
        </>}
      </section>
      <footer className="pantheon-footnote"><span>Свершения героев · обновление каждые 30 секунд</span>{updatedAt && result?.metric === metric && <span>Последнее обновление: {new Intl.DateTimeFormat("ru-RU", { hour: "2-digit", minute: "2-digit" }).format(updatedAt)}</span>}</footer>
    </main>
  )
}

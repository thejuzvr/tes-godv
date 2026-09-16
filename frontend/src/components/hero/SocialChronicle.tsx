import { useCallback, useEffect, useState } from "react"
import { RefreshCw, Users, Shield, Eye } from "lucide-react"
import { api } from "@/lib/api"
import "./social-chronicle.css"

type Mode = "disabled" | "live_only" | "async"
type Reveal = "nobody" | "encounter" | "guild" | "public"
interface Settings { encounter_mode: Mode; reveal_name: Reveal; daily_cap: number; limits: { daily_cap_max: number } }
interface Encounter { id: string; counterpart_label: string; kind: string; role: string; created_at: string }
interface Relationship { id: string; counterpart_id: string; familiarity: number; encounter_count: number; affinity: number }

const MODE_RU: Record<Mode, string> = { disabled: "Выключены", live_only: "Только в игре", async: "Также вне игры" }
const REVEAL_RU: Record<Reveal, string> = { nobody: "Не показывать", encounter: "При встрече", guild: "Только гильдии", public: "Всегда" }

export function SocialChronicle() {
  const [settings, setSettings] = useState<Settings | null>(null)
  const [encounters, setEncounters] = useState<Encounter[]>([])
  const [relationships, setRelationships] = useState<Relationship[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")

  const load = useCallback(async () => {
    setLoading(true); setError("")
    try {
      const [s, e, r] = await Promise.all([api.getHeroSocialSettings(), api.getHeroEncounters(10), api.getHeroRelationships()])
      setSettings(s); setEncounters(e.encounters || []); setRelationships(r.relationships || [])
    } catch { setError("Не удалось открыть социальную летопись. Проверьте соединение и повторите загрузку.") }
    finally { setLoading(false) }
  }, [])
  useEffect(() => { void load() }, [load])

  const update = async (patch: Partial<Pick<Settings, "encounter_mode" | "reveal_name" | "daily_cap">>) => {
    if (!settings || saving) return
    const previous = settings
    setSettings({ ...settings, ...patch }); setSaving(true); setError("")
    try { setSettings(await api.updateHeroSocialSettings(patch)) }
    catch { setSettings(previous); setError("Настройка не сохранилась. Попробуйте ещё раз.") }
    finally { setSaving(false) }
  }

  return <section className="social-chronicle" aria-labelledby="social-chronicle-title" aria-busy={loading || saving}>
    <header><div><span><Users size={16} aria-hidden="true"/> Живой мир</span><h2 id="social-chronicle-title">Встречи и знакомства</h2><p>Случайные пересечения героев в одной локации и память об этих встречах.</p></div><button onClick={() => void load()} disabled={loading} aria-label="Обновить социальную летопись"><RefreshCw size={16} aria-hidden="true"/></button></header>
    {error && <div className="social-error" role="alert">{error}</div>}
    {loading ? <p className="social-empty" role="status">Собираем записи о встречах…</p> : settings && <>
      <div className="social-settings">
        <label><span><Shield size={15} aria-hidden="true"/> Участие во встречах</span><select value={settings.encounter_mode} disabled={saving} onChange={(e) => void update({ encounter_mode: e.target.value as Mode })}>{(Object.keys(MODE_RU) as Mode[]).map(v => <option key={v} value={v}>{MODE_RU[v]}</option>)}</select></label>
        <label><span><Eye size={15} aria-hidden="true"/> Показывать имя</span><select value={settings.reveal_name} disabled={saving} onChange={(e) => void update({ reveal_name: e.target.value as Reveal })}>{(Object.keys(REVEAL_RU) as Reveal[]).map(v => <option key={v} value={v}>{REVEAL_RU[v]}</option>)}</select></label>
        <label><span>Встреч в день</span><input type="number" min={0} max={settings.limits.daily_cap_max} value={settings.daily_cap} disabled={saving} onChange={(e) => void update({ daily_cap: Number(e.target.value) })}/></label>
      </div>
      <div className="social-columns">
        <div><h3>Последние встречи</h3>{encounters.length ? <ul>{encounters.map(e => <li key={e.id}><strong>{e.counterpart_label}</strong><span>{new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(`${e.created_at}Z`))}</span></li>)}</ul> : <p className="social-empty">Встреч ещё не было. Герои должны оказаться в одной локации.</p>}</div>
        <div><h3>Знакомые</h3>{relationships.length ? <ul>{relationships.map(r => <li key={r.id}><strong>Знакомство #{r.counterpart_id.slice(0, 6)}</strong><span>{r.encounter_count} встреч · знакомство {r.familiarity}</span></li>)}</ul> : <p className="social-empty">Знакомства появятся после первой встречи.</p>}</div>
      </div>
    </>}
  </section>
}

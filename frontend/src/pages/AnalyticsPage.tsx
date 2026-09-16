import { useEffect, useState } from "react"
import { Activity, Archive, ArrowDown, Copy, Eye, Fingerprint, Fish, GitBranch, Hammer, KeyRound, PawPrint, RefreshCw, Share2, Sprout } from "lucide-react"
import { api } from "@/lib/api"
import { useGameStore, type Pet } from "@/stores/gameStore"
import { SocialChronicle } from "@/components/hero/SocialChronicle"
import "./analytics-observatory.css"

interface PetHistoryEntry extends Pet { created_at: string | null }
interface BrainData {
  brain_hash: string
  legacy: boolean
  generation: number
  archetype: string
  quirks: string[]
  traits: { trait: string; value: number; base: number | null }[]
  links: { a: string; b: string; weight: number; base_weight: number }[]
  decision_log: { day: number; hour: number | null; goal: string; utility: number | null; reasons: string[] }[]
  budget: { week: number; spent: number }
  stats: { total_kills: number; total_gold_earned: number; total_play_time_seconds: number; game_day: number; level: number; name: string }
}
const TRAIT_RU: Record<string, string> = {
  bravery: "Смелость", curiosity: "Любопытство", greed: "Жадность", sociability: "Общительность",
  tenacity: "Стойкость", caution: "Осторожность", patience: "Терпение", dexterity: "Ловкость", empathy: "Эмпатия",
}
const QUIRK_RU: Record<string, string> = {
  afraid_of_water: "Боится воды", dawn_fisher: "Рыбак на рассвете", cup_collector: "Коллекционер чашек",
  night_thief: "Ночной вор", spider_panic: "Паукофоб", braggart: "Хвастун", superstitious: "Суеверен", sweet_tooth: "Сладкоежка",
}
const ARCHETYPE_RU: Record<string, string> = {
  wanderer: "Странник", warrior: "Воин", schemer: "Интриган", socialite: "Душа компании", hermit: "Отшельник", grinder: "Труженик",
}
const GOAL_RU: Record<string, string> = {
  complete_quest: "Квест", heal: "Лечение", rest: "Отдых", explore: "Исследование", fight: "Бой", shop: "Торговля",
  socialize: "Общение", travel: "Дорога", loot: "Добыча", fish: "Рыбалка", gather: "Сбор", mining: "Горное дело", steal: "Кража",
  break_in: "Взлом", pet_care: "Питомец", __rebirth__: "Перерождение",
}
const PET_SPECIES: Record<string, { icon: string; name: string }> = {
  wolf: { icon: "🐺", name: "Волк" }, owl: { icon: "🦉", name: "Сова" },
  cat: { icon: "🐈", name: "Кот" }, lizard: { icon: "🦎", name: "Ящерица" },
}
const SKILL_META = {
  fishing: { label: "Рыболовство", note: "Ловля рыбы и терпение у воды", icon: Fish },
  gathering: { label: "Собирательство", note: "Поиск трав и полезных припасов", icon: Sprout },
  mining: { label: "Горное дело", note: "Разработка рудных жил и добыча металла", icon: Hammer },
  stealth: { label: "Скрытность", note: "Тихое движение и незаметные действия", icon: Eye },
  lockpicking: { label: "Взлом", note: "Работа с замками и закрытыми путями", icon: KeyRound },
} as const
const number = (value: number) => value.toLocaleString("ru-RU")

// Local SVGs keep the exact trait and link data; tables below provide a non-visual equivalent.
function TraitRadar({ traits }: { traits: BrainData["traits"] }) {
  const point = (i: number, value: number) => {
    const angle = Math.PI * 2 * i / traits.length - Math.PI / 2
    const radius = Math.max(0, Math.min(100, value)) / 100 * 92
    return [160 + radius * Math.cos(angle), 140 + radius * Math.sin(angle)]
  }
  const poly = (get: (trait: BrainData["traits"][number]) => number) => traits.map((t, i) => point(i, get(t)).join(",")).join(" ")
  return <svg className="ao-chart" viewBox="-40 0 400 280" role="img" aria-label="Радар черт: текущие значения и гено-база. Точные значения — под графиком.">
    {[25, 50, 75, 100].map(v => <circle key={v} cx="160" cy="140" r={v / 100 * 92} className="ao-gridline" />)}
    {traits.map((t, i) => { const [x, y] = point(i, 100); return <line key={t.trait} x1="160" y1="140" x2={x} y2={y} className="ao-gridline" /> })}
    {traits.some(t => t.base !== null) && <polygon points={poly(t => t.base ?? t.value)} className="ao-radar-base" />}
    <polygon points={poly(t => t.value)} className="ao-radar-current" />
    {traits.map((t, i) => {
      const angle = Math.PI * 2 * i / traits.length - Math.PI / 2
      return <text key={t.trait} x={160 + 112 * Math.cos(angle)} y={140 + 112 * Math.sin(angle)} textAnchor="middle" dominantBaseline="middle">{TRAIT_RU[t.trait] ?? t.trait}</text>
    })}
  </svg>
}
function LinksGraph({ links }: { links: BrainData["links"] }) {
  const nodes = [...new Set([...Object.keys(TRAIT_RU), ...links.flatMap(l => [l.a, l.b])])]
  const pos = (trait: string) => {
    const angle = Math.PI * 2 * nodes.indexOf(trait) / nodes.length - Math.PI / 2
    return [160 + 100 * Math.cos(angle), 140 + 100 * Math.sin(angle)]
  }
  return <svg className="ao-chart" viewBox="0 0 320 280" role="img" aria-label="Микросвязи черт. Толщина — сила, яркость — изменение опытом. Точные значения доступны в таблице связей.">
    <circle cx="160" cy="140" r="100" className="ao-gridline" />
    {links.map(l => {
      const [x1, y1] = pos(l.a), [x2, y2] = pos(l.b)
      return <line key={`${l.a}-${l.b}`} x1={x1} y1={y1} x2={x2} y2={y2}
        stroke={l.weight >= 0 ? "var(--ao-positive)" : "var(--ao-negative)"}
        strokeWidth={0.5 + Math.abs(l.weight) * 2.5} strokeOpacity={Math.abs(l.weight - l.base_weight) > 0.02 ? 0.95 : 0.4}>
        <title>{`${TRAIT_RU[l.a] ?? l.a} × ${TRAIT_RU[l.b] ?? l.b}: ${l.weight.toFixed(2)} (база ${l.base_weight.toFixed(2)})`}</title>
      </line>
    })}
    {nodes.map(t => { const [x, y] = pos(t); return <g key={t}><circle cx={x} cy={y} r="17" className="ao-node" /><text x={x} y={y} textAnchor="middle" dominantBaseline="middle">{(TRAIT_RU[t] ?? t).slice(0, 3)}</text></g> })}
  </svg>
}
function petDate(value: string | null) {
  if (!value) return "Дата появления не записана"
  const date = new Date(/(?:Z|[+-]\d{2}:?\d{2})$/i.test(value) ? value : `${value}Z`)
  return Number.isNaN(date.getTime()) ? "Дата появления не записана" : `Появился ${date.toLocaleDateString("ru-RU")}`
}

export function AnalyticsPage() {
  const hero = useGameStore(state => state.hero)
  const [brain, setBrain] = useState<BrainData | null>(null)
  const [petHistory, setPetHistory] = useState<PetHistoryEntry[] | null>(null)
  const [loading, setLoading] = useState(true)
  const [petsLoading, setPetsLoading] = useState(true)
  const [failed, setFailed] = useState(false)
  const [attempt, setAttempt] = useState(0)
  const [petAttempt, setPetAttempt] = useState(0)
  const [notice, setNotice] = useState("")
  const [goalFilter, setGoalFilter] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    api.getBrain().then(data => { if (active) { setBrain(data); setFailed(false) } })
      .catch(() => { if (active) { setBrain(null); setFailed(true) } })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [attempt])
  useEffect(() => {
    let active = true
    api.getPetHistory().then(data => { if (active) setPetHistory(data.pets) })
      .catch(() => { if (active) setPetHistory(null) })
      .finally(() => { if (active) setPetsLoading(false) })
    return () => { active = false }
  }, [petAttempt])

  const copy = async (text: string, label: string) => {
    try {
      if (!navigator.clipboard) throw new Error("Clipboard unavailable")
      await navigator.clipboard.writeText(text)
      setNotice(label)
    } catch { setNotice("Не удалось скопировать. Разрешите доступ к буферу обмена в браузере.") }
  }
  const shareSummary = () => {
    if (!brain) return
    const top = [...brain.traits].sort((a, b) => b.value - a.value).slice(0, 3).map(t => `${TRAIT_RU[t.trait] ?? t.trait} ${t.value}`).join(", ")
    void copy(`🧠 Мозг героя «${brain.stats.name}» (TES Idle)\nПоколение: ${brain.generation} · Архетип: ${ARCHETYPE_RU[brain.archetype] ?? brain.archetype}\nДоминирующие черты: ${top}\nДень ${brain.stats.game_day} · Ур. ${brain.stats.level} · Убийств: ${brain.stats.total_kills}\nHash: ${brain.brain_hash.slice(0, 16)}…`, "Сводка скопирована в буфер обмена.")
  }
  const header = <header className="ao-heading"><div><p className="ao-eyebrow"><Archive size={15} aria-hidden="true" /> Обсерватория / архив героя</p><h1>Аналитика</h1><p className="ao-intro">Характер складывается из решений. Здесь остаётся их след.</p></div>{brain && <a className="ao-button" href="#ao-decisions">К решениям <ArrowDown size={15} aria-hidden="true" /></a>}</header>
  if (loading) return <div className="analytics-observatory">{header}<section className="ao-state" role="status" aria-busy="true"><Activity size={28} aria-hidden="true" /><h2>Собираем архив</h2><p>Загружаем черты, связи и решения героя…</p></section></div>
  if (!brain) return <div className="analytics-observatory">{header}<section className="ao-state" role={failed ? "alert" : "status"}><Archive size={28} aria-hidden="true" /><h2>{failed ? "Архив недоступен" : "Герой не найден"}</h2><p>{failed ? "Не удалось загрузить аналитику. Проверьте соединение и попробуйте снова." : "Аналитика появится, когда у вас будет герой."}</p><button className="ao-button" onClick={() => { setLoading(true); setAttempt(v => v + 1) }}><RefreshCw size={15} aria-hidden="true" /> Повторить загрузку</button></section></div>

  const budgetLeft = Math.max(0, 10 - (brain.budget.spent || 0))
  const decisionLog = [...brain.decision_log].reverse().filter(d => !goalFilter || d.goal === goalFilter)
  const counts = new Map<string, number>()
  for (const d of brain.decision_log) counts.set(d.goal, (counts.get(d.goal) || 0) + 1)
  const goals = [...counts.entries()].sort((a, b) => b[1] - a[1])
  const hasBase = brain.traits.some(t => t.base != null)
  const skills = hero?.skills
  const recordedSkills = skills
    ? (Object.entries(SKILL_META) as [keyof typeof SKILL_META, (typeof SKILL_META)[keyof typeof SKILL_META]][])
        .map(([key, meta]) => ({ key, meta, value: Number(skills[key]) }))
        .filter(skill => Number.isFinite(skill.value))
    : []

  return <div className="analytics-observatory">
    {header}
    <section className="ao-passport" aria-labelledby="ao-passport-title">
      <div className="ao-identity"><p className="ao-eyebrow"><Fingerprint size={16} aria-hidden="true" /> Паспорт мозга</p><h2 id="ao-passport-title">{brain.stats.name}</h2><div className="ao-tags"><span>{ARCHETYPE_RU[brain.archetype] ?? brain.archetype}</span><span>Поколение {number(brain.generation)}</span></div><p className="ao-muted">{brain.quirks.length ? brain.quirks.map(q => QUIRK_RU[q] ?? q).join(" · ") : "Причуды не записаны"}</p></div>
      <div className="ao-fingerprint"><span className="ao-label">Уникальный отпечаток</span><code>{brain.brain_hash}</code><div className="ao-actions"><button className="ao-button" onClick={() => void copy(brain.brain_hash, "Hash скопирован в буфер обмена.")}><Copy size={14} aria-hidden="true" /> Копировать hash</button><button className="ao-button ao-button-accent" onClick={shareSummary}><Share2 size={14} aria-hidden="true" /> Поделиться сводкой</button></div><p className="ao-notice" role="status">{notice}</p></div>
      <div className="ao-plasticity"><span className="ao-label">Пластичность · неделя {brain.budget.week}</span><p><strong>{budgetLeft.toFixed(1)}</strong><span> п. осталось</span></p><meter min={0} max={10} value={Math.min(10, budgetLeft)} aria-label="Оставшаяся пластичность" /><span className="ao-muted">Из недельного запаса 10 п.</span></div>
      {brain.legacy && <p className="ao-legacy">Герой создан до эры Мозга — сравнение с гено-базой недоступно.</p>}
    </section>
    <dl className="ao-stats" aria-label="Статистика героя">{[
      { label: "Уровень", value: number(brain.stats.level) }, { label: "Игровой день", value: number(brain.stats.game_day) },
      { label: "Убийств", value: number(brain.stats.total_kills) }, { label: "Золота заработано", value: number(brain.stats.total_gold_earned) },
      { label: "Время в мире", value: `${number(Math.round(brain.stats.total_play_time_seconds / 60))} мин` }, { label: "Решений в логе", value: number(brain.decision_log.length) },
    ].map(stat => <div key={stat.label}><dt>{stat.label}</dt><dd>{stat.value}</dd></div>)}</dl>
    <div className="ao-charts">
      <section className="ao-panel" aria-labelledby="ao-traits"><header className="ao-section-heading"><div><p className="ao-eyebrow"><Activity size={15} aria-hidden="true" /> Характер</p><h2 id="ao-traits">Радар черт</h2></div><span className="ao-scale">0 — 100</span></header>
        {brain.traits.length === 0 ? <p className="ao-empty">Черты пока не записаны.</p> : <><TraitRadar traits={brain.traits} /><p className="ao-chart-caption">Сплошная линия — сейчас{hasBase ? " · пунктир — гено-база" : " · гено-база недоступна"}</p><div className="ao-trait-list">{brain.traits.map(t => <div key={t.trait}><span>{TRAIT_RU[t.trait] ?? t.trait}</span><strong>{t.value}</strong><span className="ao-base">база {t.base ?? "—"}</span></div>)}</div></>}
      </section>
      <section className="ao-panel" aria-labelledby="ao-links"><header className="ao-section-heading"><div><p className="ao-eyebrow"><GitBranch size={15} aria-hidden="true" /> Влияние черт</p><h2 id="ao-links">Микросвязи</h2></div></header>
        {brain.links.length === 0 ? <p className="ao-empty">Связи между чертами пока не записаны.</p> : <><LinksGraph links={brain.links} /><p className="ao-chart-caption">Толщина — сила · яркие связи изменились опытом</p><div className="ao-legend"><span className="ao-positive">+ усиливающие</span><span className="ao-negative">− подавляющие</span></div><details className="ao-link-details"><summary>Все связи · {brain.links.length}</summary><div className="ao-table-scroll" tabIndex={0} role="region" aria-label="Таблица микросвязей"><table><caption className="ao-sr-only">Текущий вес и гено-база каждой связи</caption><thead><tr><th scope="col">Связь</th><th scope="col">Сейчас</th><th scope="col">База</th></tr></thead><tbody>{brain.links.map(l => <tr key={`${l.a}-${l.b}`}><th scope="row">{TRAIT_RU[l.a] ?? l.a} × {TRAIT_RU[l.b] ?? l.b}</th><td>{l.weight.toFixed(2)}</td><td>{l.base_weight.toFixed(2)}</td></tr>)}</tbody></table></div></details></>}
      </section>
    </div>
    {recordedSkills.length > 0 && <details className="ao-panel ao-skills">
      <summary><span><Activity size={15} aria-hidden="true" /><span><b>Прикладные навыки</b><small>Мастерство занятий · {recordedSkills.length}</small></span></span><span className="ao-skills-disclosure" aria-hidden="true">Развернуть</span></summary>
      <div className="ao-skills-grid">
        {recordedSkills.map(({ key, meta, value }) => { const Icon = meta.icon; const normalized = Math.min(100, Math.max(0, value)); return <article key={key} className="ao-skill"><Icon size={18} aria-hidden="true" /><div><h3>{meta.label}</h3><p>{meta.note}</p></div><strong>{Math.round(value)}</strong><div className="ao-skill-track" role="progressbar" aria-label={`${meta.label}: ${Math.round(value)} из 100`} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(normalized)}><i style={{ width: `${normalized}%` }} /></div></article> })}
      </div>
    </details>}
    <section className="ao-panel ao-decisions" id="ao-decisions" aria-labelledby="ao-decisions-title"><header className="ao-section-heading"><div><p className="ao-eyebrow"><Archive size={15} aria-hidden="true" /> Архив выбора</p><h2 id="ao-decisions-title">Хроника решений</h2><p className="ao-muted">Что выбрал герой и почему. Свежие записи — первыми.</p></div><span className="ao-scale">Последние 50</span></header>
      {brain.decision_log.length === 0 ? <p className="ao-empty">Герой ещё не принимал решений. Первые записи появятся после игровых тиков.</p> : <><div className="ao-filters" role="group" aria-label="Фильтр решений по цели"><button aria-pressed={goalFilter === null} onClick={() => setGoalFilter(null)}>Все <span>{brain.decision_log.length}</span></button>{goals.map(([goal, count]) => <button key={goal} aria-pressed={goalFilter === goal} onClick={() => setGoalFilter(goal === goalFilter ? null : goal)}>{GOAL_RU[goal] ?? goal}<span>{count}</span></button>)}</div><div className="ao-log" tabIndex={0} role="region" aria-label="Решения героя"><ol>{decisionLog.map((d, i) => <li key={`${d.day}-${d.hour}-${i}`} className={d.goal === "__rebirth__" ? "ao-rebirth" : undefined}><div className="ao-log-time">День {d.day}<span>{d.hour != null ? `${d.hour}ч` : "Час не записан"}</span></div><div className="ao-log-content"><h3>{GOAL_RU[d.goal] ?? d.goal}</h3><p>{d.reasons?.join(" · ") || "Причины не записаны"}</p></div>{d.utility != null && <div className="ao-utility"><span>Полезность</span><strong>{d.utility.toFixed(2)}</strong></div>}</li>)}</ol>{decisionLog.length === 0 && <p className="ao-empty">Решений с этой целью нет. Выберите другой фильтр.</p>}</div><p className="ao-log-count" role="status">Показано {decisionLog.length} из {brain.decision_log.length} записей</p></>}
    </section>
    <section className="ao-panel ao-pets" aria-labelledby="ao-pets-title"><header className="ao-section-heading"><div><p className="ao-eyebrow"><PawPrint size={15} aria-hidden="true" /> Спутники пути</p><h2 id="ao-pets-title">История питомцев</h2><p className="ao-muted">Те, кто ушёл навсегда. Их след остаётся в архиве.</p></div></header>
      {petsLoading ? <p className="ao-empty" role="status">Загружаем историю питомцев…</p> : petHistory === null ? <div className="ao-empty"><p role="alert">Не удалось загрузить историю питомцев.</p><button className="ao-button" onClick={() => { setPetsLoading(true); setPetAttempt(v => v + 1) }}><RefreshCw size={14} aria-hidden="true" /> Повторить</button></div> : petHistory.length === 0 ? <p className="ao-empty">Пока никто не уходил. Питомец покидает героя, только если лояльность упала до нуля.</p> : <ul className="ao-pet-list">{petHistory.map(p => { const sp = PET_SPECIES[p.species] ?? { icon: "🐾", name: p.species }; return <li key={p.id}><span className="ao-pet-icon" aria-hidden="true">{sp.icon}</span><div><h3>{p.name}</h3><p>{sp.name} · {petDate(p.created_at)}</p></div><span className="ao-pet-loyalty">Верность {p.loyalty}</span></li> })}</ul>}
    </section>
    <SocialChronicle />
    <footer className="ao-footer">Архив показывает текущее состояние героя и сохранённую историю решений.</footer>
  </div>
}

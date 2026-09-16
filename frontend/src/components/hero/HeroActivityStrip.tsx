import { Brain, Eye, Fish, Footprints, Hammer, Hourglass, KeyRound, Sprout } from "lucide-react"
import type { Hero } from "@/stores/gameStore"

const SKILLS = {
  fishing: { label: "Рыболовство", icon: Fish },
  gathering: { label: "Собирательство", icon: Sprout },
  mining: { label: "Горное дело", icon: Hammer },
  stealth: { label: "Скрытность", icon: Eye },
  lockpicking: { label: "Взлом", icon: KeyRound },
} as const

const ACTIVITY_RU: Record<string, string> = {
  fishing: "Рыбалка",
  gathering: "Сбор",
  mining: "Добыча руды",
  traveling: "Путешествие",
  jailed: "Заключение",
  stealing: "Кража",
  breaking_in: "Взлом",
  pet_care: "Забота о питомце",
}

const PHASE_RU: Record<string, string> = {
  preparing: "подготовка",
  active: "в процессе",
  resolving: "завершение",
  traveling: "в пути",
  fishing: "ловля",
  gathering: "поиск",
  mining: "разработка жилы",
  serving: "отбывает срок",
}

const GOAL_RU: Record<string, string> = {
  complete_quest: "завершить квест",
  heal: "вылечиться",
  rest: "отдохнуть",
  explore: "исследовать мир",
  fight: "вступить в бой",
  shop: "заняться торговлей",
  socialize: "пообщаться",
  travel: "отправиться в путь",
  loot: "найти добычу",
  fish: "порыбачить",
  gather: "собрать припасы",
  mining: "добыть руду",
  steal: "совершить кражу",
  break_in: "проникнуть внутрь",
  pet_care: "позаботиться о питомце",
}

type HeroIntent = {
  goal: string
  heldDecisions?: number
  frustration?: number
}

function finiteNumber(value: unknown) {
  const parsed = typeof value === "number" ? value : Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function readIntent(stateData: Hero["state_data"]): HeroIntent | null {
  try {
    const root: unknown = typeof stateData === "string" ? JSON.parse(stateData || "{}") : stateData
    if (!root || typeof root !== "object") return null
    const brain = (root as Record<string, unknown>).brain
    if (!brain || typeof brain !== "object") return null
    const intent = (brain as Record<string, unknown>).intent
    if (!intent || typeof intent !== "object") return null

    const record = intent as Record<string, unknown>
    const goal = typeof record.goal === "string" ? record.goal.trim() : ""
    if (!goal) return null

    const held = finiteNumber(record.held_decisions)
    const frustration = finiteNumber(record.frustration)
    return {
      goal,
      heldDecisions: held === null ? undefined : Math.max(0, Math.trunc(held)),
      frustration: frustration === null ? undefined : Math.max(0, frustration),
    }
  } catch {
    return null
  }
}

function tickLabel(value: number) {
  const mod10 = value % 10
  const mod100 = value % 100
  if (mod10 === 1 && mod100 !== 11) return "тик"
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return "тика"
  return "тиков"
}

export function HeroActivityStrip({ hero }: { hero: Hero }) {
  const activity = hero.activity
  const intent = readIntent(hero.state_data)
  const skills = hero.skills
  const visibleSkills = skills
    ? (Object.entries(SKILLS) as [keyof typeof SKILLS, (typeof SKILLS)[keyof typeof SKILLS]][])
        .flatMap(([key, meta]) => {
          const value = finiteNumber(skills[key])
          return value !== null && value > 0 ? [{ key, meta, value }] : []
        })
    : []

  if (!activity && !intent && visibleSkills.length === 0) return null

  const totalRaw = finiteNumber(activity?.total_ticks)
  const doneRaw = finiteNumber(activity?.ticks_done)
  const leftRaw = finiteNumber(activity?.ticks_left)
  const total = totalRaw !== null && totalRaw > 0 ? totalRaw : null
  const hasProgress = total !== null && doneRaw !== null
  const done = total !== null && doneRaw !== null ? Math.min(total, Math.max(0, doneRaw)) : 0
  const activityPct = total === null ? 0 : Math.round(done / total * 100)
  const ticksLeft = leftRaw === null ? null : Math.max(0, Math.trunc(leftRaw))

  return (
    <section className="hero-activity-strip" aria-label="Занятие, намерение и мастерство героя">
      {(activity || intent) && (
        <div className="hero-live-signals">
          {activity && (
            <div className="hero-current-activity">
              <span className="hero-activity-icon" aria-hidden="true">{activity.kind === "traveling" ? <Footprints size={18} /> : <Hourglass size={18} />}</span>
              <div className="hero-activity-copy">
                <span>
                  <b>Сейчас</b> · {ACTIVITY_RU[activity.kind] || activity.kind}
                  {activity.phase ? <em> · {PHASE_RU[activity.phase] || activity.phase}</em> : null}
                  {activity.target_name ? <small>Цель: {activity.target_name}</small> : null}
                </span>
                {ticksLeft !== null && <strong>{ticksLeft > 0 ? `осталось ${ticksLeft} ${tickLabel(ticksLeft)}` : "завершает"}</strong>}
              </div>
              {hasProgress && (
                <div className="hero-activity-progress" role="progressbar" aria-label={`Прогресс занятия: ${activityPct}%`} aria-valuemin={0} aria-valuemax={100} aria-valuenow={activityPct}>
                  <i style={{ width: `${activityPct}%` }} />
                </div>
              )}
            </div>
          )}
          {intent && (
            <div className="hero-current-intent">
              <Brain size={18} aria-hidden="true" />
              <div>
                <span>Намерение</span>
                <strong>{GOAL_RU[intent.goal] || intent.goal}</strong>
              </div>
              {(intent.heldDecisions !== undefined || intent.frustration !== undefined) && (
                <dl aria-label="Устойчивость намерения">
                  {intent.heldDecisions !== undefined && <div><dt>Удерживает</dt><dd>{intent.heldDecisions} реш.</dd></div>}
                  {intent.frustration !== undefined && <div><dt>Фрустрация</dt><dd>{Math.round(intent.frustration * 100)}%</dd></div>}
                </dl>
              )}
            </div>
          )}
        </div>
      )}
      {visibleSkills.length > 0 && (
        <div className="hero-skill-list" aria-label="Навыки занятий">
          {visibleSkills.map(({ key, meta, value }) => {
            const Icon = meta.icon
            const normalized = Math.min(100, Math.max(0, value))
            return <div className="hero-skill" key={key} title={`${meta.label}: ${value.toFixed(1)} из 100`}><Icon size={15} aria-hidden="true" /><span>{meta.label}</span><strong>{Math.round(value)}</strong><i aria-hidden="true"><b style={{ width: `${normalized}%` }} /></i></div>
          })}
        </div>
      )}
    </section>
  )
}

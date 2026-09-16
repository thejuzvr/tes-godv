import { useEffect, useId, useRef, useState, type MouseEvent } from "react"
import { Zap, Sparkles, Heart, Compass, Scroll, CloudRain, Clock, Check, CircleAlert, LoaderCircle } from "lucide-react"

const actions = [
  { type: "encourage", icon: Sparkles, label: "Вдохновить", desc: "+15 мораль" },
  { type: "punish", icon: Zap, label: "Наказать", desc: "−10 мораль" },
  { type: "heal", icon: Heart, label: "Исцелить", desc: "+30 HP" },
  { type: "direct", icon: Compass, label: "Направить", desc: "Смена цели" },
  { type: "quest", icon: Scroll, label: "Задание", desc: "Новый квест" },
  { type: "weather", icon: CloudRain, label: "Погода", desc: "Знак небес" },
] as const

// Preserve the existing five-second pause after each request settles.
const COOLDOWN_MS = 5000

export function GodPanel({ onAction, hero }: { onAction: (t: string) => Promise<string | null>; hero: any }) {
  const id = useId()
  const [pending, setPending] = useState(false)
  const [secondsLeft, setSecondsLeft] = useState(0)
  const [lastAction, setLastAction] = useState<string | null>(null)
  const [narrative, setNarrative] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const locked = useRef(false)
  const timer = useRef<ReturnType<typeof setInterval> | null>(null)
  const lifetime = useRef({ active: false })

  useEffect(() => {
    const current = { active: true }
    lifetime.current = current
    return () => {
      current.active = false
      if (timer.current !== null) {
        clearInterval(timer.current)
        timer.current = null
      }
    }
  }, [])

  const handleActionClick = async (event: MouseEvent<HTMLButtonElement>) => {
    const action = actions.find(({ type }) => type === event.currentTarget.dataset.action)
    if (!action || locked.current) return

    const current = lifetime.current
    locked.current = true
    setPending(true)
    setLastAction(action.label)
    setNarrative(null)
    setError(null)

    try {
      const text = await onAction(action.type)
      if (current.active) setNarrative(text)
    } catch (cause: unknown) {
      if (current.active) {
        const detail = cause instanceof Error ? cause.message : typeof cause === "string" ? cause : ""
        setError(detail.trim() || "Не удалось выполнить вмешательство.")
      }
    } finally {
      // A settled request must not update state or start a timer after unmount.
      if (current.active) {
        setPending(false)
        setSecondsLeft(COOLDOWN_MS / 1000)
        const deadline = Date.now() + COOLDOWN_MS
        timer.current = setInterval(() => {
          const remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000))
          setSecondsLeft(remaining)
          if (remaining === 0) {
            locked.current = false
            if (timer.current !== null) clearInterval(timer.current)
            timer.current = null
          }
        }, 250)
      }
    }
  }

  const soulEnergy = Number(hero?.soul_energy ?? 0)
  const soulPct = Number.isFinite(soulEnergy) ? Math.min(100, Math.max(0, Math.round(soulEnergy))) : 0
  const disabled = pending || secondsLeft > 0
  const state = pending ? "pending" : secondsLeft > 0 ? "cooldown" : "ready"

  return (
    <section className="observatory-intervention" aria-labelledby={`${id}-title`}>
      <header className="observatory-intervention-header">
        <div className="observatory-intervention-heading">
          <Sparkles className="observatory-intervention-icon" size={20} aria-hidden="true" />
          <h2 id={`${id}-title`} className="observatory-intervention-title">Вмешательство</h2>
        </div>
        <p id={`${id}-availability`} className={`observatory-intervention-availability observatory-intervention-availability--${state}`}>
          {pending ? <LoaderCircle size={16} aria-hidden="true" /> : secondsLeft > 0 ? <Clock size={16} aria-hidden="true" /> : <Check size={16} aria-hidden="true" />}
          <span>{pending ? "Ожидаем ответ…" : secondsLeft > 0 ? `Восстановление · ${secondsLeft} с` : "Готово к вмешательству"}</span>
        </p>
      </header>

      <div className="observatory-intervention-body">
        <div className="observatory-intervention-energy">
          <div className="observatory-intervention-energy-heading">
            <label id={`${id}-energy-label`} htmlFor={`${id}-energy`} className="observatory-intervention-energy-label">Сила Душ</label>
            <span className="observatory-intervention-energy-value">{soulPct}%</span>
          </div>
          <meter id={`${id}-energy`} className="observatory-intervention-energy-meter" min={0} max={100} value={soulPct} aria-labelledby={`${id}-energy-label`}>{soulPct}%</meter>
        </div>

        <div className="observatory-intervention-actions" role="group" aria-label="Действия вмешательства" aria-busy={pending} aria-describedby={`${id}-availability`}>
          {actions.map(({ type, icon: Icon, label, desc }) => (
            <button
              key={type}
              type="button"
              className={`observatory-intervention-action observatory-intervention-action--${type}`}
              data-action={type}
              onClick={handleActionClick}
              disabled={disabled}
            >
              <Icon className="observatory-intervention-action-icon" size={20} aria-hidden="true" />
              <span className="observatory-intervention-action-copy">
                <span className="observatory-intervention-action-label">{label}</span>
                <span className="observatory-intervention-action-effect">{desc}</span>
              </span>
            </button>
          ))}
        </div>

        <div className={`observatory-intervention-feedback${error ? " observatory-intervention-feedback--error" : ""}`} role="status" aria-live="polite" aria-atomic="true">
          {lastAction && (
            <>
              <p className="observatory-intervention-feedback-title">
                {pending ? <LoaderCircle size={16} aria-hidden="true" /> : error ? <CircleAlert size={16} aria-hidden="true" /> : <Check size={16} aria-hidden="true" />}
                <span>{pending ? `«${lastAction}»: выполняется…` : error ? `«${lastAction}»: не выполнено` : `«${lastAction}»: выполнено`}</span>
              </p>
              {error ? (
                <>
                  <p className="observatory-intervention-error">{error}</p>
                  <p className="observatory-intervention-hint">Повторите попытку после восстановления.</p>
                </>
              ) : narrative && <p className="observatory-intervention-narrative">{narrative}</p>}
            </>
          )}
        </div>
      </div>
    </section>
  )
}

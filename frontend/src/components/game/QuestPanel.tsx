import { useEffect, useState } from "react"
import { api } from "@/lib/api"

/* ─── Quest Panel — активное задание из API, без дефолтных моков ─── */
export function QuestPanel({ refreshTrigger = 0 }: { refreshTrigger?: number }) {
  const [quest, setQuest] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(false)

  useEffect(() => {
    setLoading(true)
    api.getActiveQuest().then(setQuest).catch(() => setQuest(null)).finally(() => setLoading(false))
  }, [refreshTrigger])

  const generate = async () => {
    setGenerating(true)
    try {
      await api.generateQuest()
      setQuest(await api.getActiveQuest())
    } catch { /* бэк отклонит, если задание уже появилось — перечитаем ниже по тику */ }
    finally { setGenerating(false) }
  }

  if (loading) {
    return (
      <div className="panel">
        <div className="panel-header">
          <div className="flex items-center gap-2">
            <span className="panel-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg></span>
            Активное задание
          </div>
        </div>
        <div className="panel-body"><span style={{ color: "var(--muted)", fontSize: "var(--text-sm)" }}>Загрузка…</span></div>
      </div>
    )
  }

  if (!quest) {
    return (
      <div className="panel">
        <div className="panel-header">
          <div className="flex items-center gap-2">
            <span className="panel-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg></span>
            Активное задание
          </div>
        </div>
        <div className="panel-body" style={{ textAlign: "center" }}>
          <div style={{ color: "var(--muted)", fontSize: "var(--text-sm)", lineHeight: 1.6, marginBottom: "var(--space-3)" }}>Свободен от заданий — герой живёт своими делами.</div>
          <button onClick={generate} disabled={generating} style={{ padding: "7px 16px", fontSize: "var(--text-xs)", fontWeight: 600, background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-sm)", opacity: generating ? 0.5 : 1, cursor: generating ? "wait" : "pointer" }}>
            {generating ? "Размышляет…" : "Попросить задание"}
          </button>
        </div>
      </div>
    )
  }

  const progress = quest.steps_total > 0 ? (quest.current_step - 1) / quest.steps_total * 100 : 0

  return (
    <div className="panel">
      <div className="panel-header">
        <div className="flex items-center gap-2">
          <span className="panel-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg></span>
          Активное задание
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)", fontWeight: 400, textTransform: "none", letterSpacing: 0 }}>{quest.difficulty}</span>
        </div>
      </div>
      <div className="panel-body">
        <div className="quest-title"><span>📜</span> {quest.name}</div>
        <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)", marginBottom: "var(--space-2)" }}>{quest.description}</div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: "var(--text-xs)", color: "var(--muted)", fontFamily: "var(--font-mono)", marginBottom: "var(--space-2)" }}>
          <span>Прогресс</span><span>{quest.current_step - 1} / {quest.steps_total} шагов</span>
        </div>
        <div className="quest-progress-bar"><div className="quest-progress-fill" style={{ width: `${progress}%` }} /></div>
        <div className="quest-steps">
          {quest.steps.map((s: any, i: number) => (
            <div key={i} className={`quest-step ${s.status}`}>
              <span className="quest-step-icon">
                {s.status === "done" && <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3"><polyline points="20 6 9 17 4 12"/></svg>}
                {s.status === "active" && <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"/></svg>}
                {s.status === "pending" && <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" opacity="0.4"><circle cx="12" cy="12" r="10"/></svg>}
              </span>
              <span className="quest-step-text">{s.description}</span>
            </div>
          ))}
        </div>
        <div style={{ marginTop: "var(--space-3)", display: "flex", gap: "var(--space-2)" }}>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--muted)" }}>Награда: {quest.xp_reward} XP, {quest.gold_reward} золота</span>
        </div>
      </div>
    </div>
  )
}

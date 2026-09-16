/* ─── Needs Panel — потребности героя (голод / усталость / мораль) ─── */
export function NeedsPanel({ hero }: { hero: any }) {
  const needs = [
    { icon: "🍖", label: "Голод", value: `${Math.round(hero.hunger)}%`, color: hero.hunger > 70 ? "var(--warn)" : "var(--success)" },
    { icon: "😴", label: "Усталость", value: `${Math.round(hero.fatigue)}%`, color: hero.fatigue > 70 ? "var(--warn)" : "var(--success)" },
    { icon: "😊", label: "Мораль", value: `${Math.round(hero.morale)}%`, color: hero.morale > 50 ? "var(--success)" : "var(--warn)" },
  ]
  return (
    <div className="panel">
      <div className="panel-header">
        <div className="flex items-center gap-2">
          <span className="panel-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2a10 10 0 1 0 10 10H12V2z"/><path d="M20.66 7A10 10 0 0 0 7 20.66"/></svg>
          </span>
          Потребности
        </div>
      </div>
      <div className="panel-body">
        <div className="needs-grid">
          {needs.map((n, i) => (
            <div key={i} className="need-item">
              <span className="need-icon">{n.icon}</span>
              <span className="need-label">{n.label}</span>
              <span className="need-value" style={{ color: n.color }}>{n.value}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

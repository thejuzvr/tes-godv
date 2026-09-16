interface StatBarProps {
  label: string
  value: number
  max: number
  color: string
}

export function StatBar({ label, value, max, color }: StatBarProps) {
  const pct = max > 0 ? (value / max) * 100 : 0
  return (
    <div className="stat-bar">
      <div className="stat-bar-header">
        <span className="stat-bar-label" style={{ color: `var(--${color})` }}>{label}</span>
        <span className="stat-bar-value">{value} / {max}</span>
      </div>
      <div className="stat-bar-track">
        <div className={`stat-bar-fill ${color} anim-bar-fill`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  )
}

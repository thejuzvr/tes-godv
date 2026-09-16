import { useEffect, useRef } from "react"

/* ─── Mood Panel — график настроения, цвета из токенов темы ─── */
export function MoodPanel({ mood, moodHistory }: { mood: number; moodHistory: number[] }) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const category = mood > 65 ? "Боевой дух" : mood > 35 ? "Норма" : "Уныние"
  const emoji = mood > 65 ? "⚔️" : mood > 35 ? "😐" : "😔"

  // Calculate trend from last 2 points
  const trend = moodHistory.length >= 2
    ? moodHistory[moodHistory.length - 1] - moodHistory[moodHistory.length - 2]
    : 0
  const trendText = trend > 0
    ? `+${Math.round(trend)}% за последний тик`
    : trend < 0
    ? `${Math.round(trend)}% за последний тик`
    : "без изменений"

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext("2d")
    if (!ctx) return
    const dpr = window.devicePixelRatio || 1

    const draw = () => {
      const rect = canvas!.getBoundingClientRect()
      canvas!.width = rect.width * dpr
      canvas!.height = 80 * dpr
      canvas!.style.height = "80px"
      ctx!.scale(dpr, dpr)

      const w = rect.width, h = 80, p = 4
      const graphData = moodHistory.length > 0 ? moodHistory : [mood]
      const stepX = graphData.length > 1 ? (w - p * 2) / (graphData.length - 1) : 0
      const mapY = (v: number) => h - p - (v / 100) * (h - p * 2)

      // Colors from theme tokens (Ночной уголь / Пергамент)
      const fg = getComputedStyle(document.documentElement).getPropertyValue("--fg").trim() || "#e6d9bd"
      const withAlpha = (hex: string, a: number) => {
        const m = hex.replace("#", "")
        const v = m.length === 3 ? m.split("").map((c) => c + c).join("") : m
        const n = parseInt(v, 16)
        return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`
      }

      // Gradient fill
      const grad = ctx!.createLinearGradient(0, 0, 0, h)
      grad.addColorStop(0, withAlpha(fg, 0.08))
      grad.addColorStop(1, withAlpha(fg, 0))

      if (graphData.length > 1) {
        ctx!.beginPath()
        ctx!.moveTo(p, mapY(graphData[0]))
        for (let i = 1; i < graphData.length; i++) {
          const cx = p + i * stepX, cy = mapY(graphData[i])
          const px = p + (i - 1) * stepX, py = mapY(graphData[i - 1])
          ctx!.bezierCurveTo((px + cx) / 2, py, (px + cx) / 2, cy, cx, cy)
        }
        ctx!.lineTo(w - p, h)
        ctx!.lineTo(p, h)
        ctx!.closePath()
        ctx!.fillStyle = grad
        ctx!.fill()

        // Line
        ctx!.beginPath()
        ctx!.moveTo(p, mapY(graphData[0]))
        for (let i = 1; i < graphData.length; i++) {
          const cx = p + i * stepX, cy = mapY(graphData[i])
          const px = p + (i - 1) * stepX, py = mapY(graphData[i - 1])
          ctx!.bezierCurveTo((px + cx) / 2, py, (px + cx) / 2, cy, cx, cy)
        }
        ctx!.strokeStyle = fg
        ctx!.lineWidth = 2
        ctx!.stroke()

        // Dot
        const lx = p + (graphData.length - 1) * stepX
        const ly = mapY(graphData[graphData.length - 1])
        ctx!.beginPath()
        ctx!.arc(lx, ly, 4, 0, Math.PI * 2)
        ctx!.fillStyle = fg
        ctx!.fill()
        ctx!.beginPath()
        ctx!.arc(lx, ly, 7, 0, Math.PI * 2)
        ctx!.strokeStyle = withAlpha(fg, 0.15)
        ctx!.lineWidth = 2
        ctx!.stroke()
      } else {
        // Single point — just draw a dot
        ctx!.beginPath()
        ctx!.arc(w / 2, mapY(graphData[0]), 4, 0, Math.PI * 2)
        ctx!.fillStyle = fg
        ctx!.fill()
      }
    }

    draw()
    window.addEventListener("resize", draw)
    const themeObs = new MutationObserver(draw)
    themeObs.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] })
    return () => {
      window.removeEventListener("resize", draw)
      themeObs.disconnect()
    }
  }, [moodHistory, mood])

  return (
    <div className="panel mood-graph">
      <div className="panel-header">
        <div className="flex items-center gap-2">
          <span className="panel-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M22 12h-4l-3 9L9 3l-3 9H2"/></svg>
          </span>
          Настроение героя
        </div>
      </div>
      <div className="panel-body">
        <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", marginBottom: "var(--space-2)" }}>
          <span className="mood-emoji">{emoji}</span>
          <div>
            <div className="mood-label">{category}</div>
            <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
              {Math.round(mood)}% · {trendText}
            </div>
          </div>
        </div>
        <canvas ref={canvasRef} />
      </div>
    </div>
  )
}

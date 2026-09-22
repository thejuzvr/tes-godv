import { useState } from "react"
import { api } from "@/lib/api"
import { useGameStore } from "@/stores/gameStore"

const races = ["Норд", "Имперец", "Бретонец", "Редгард", "Альтмер", "Босмер", "Данмер", "Орк", "Каджит", "Аргонианин"]
const classes = ["Воин", "Маг", "Вор", "Разбойник", "Охотник", "Жрец", "Паладин", "Ассасин"]
const origins = [
  { id: "beggar", label: "Нищий", note: "Ривервуд, без монеты" },
  { id: "mage_student", label: "Ученик магов", note: "Солитьюд, в робе" },
  { id: "levy", label: "Ополченец", note: "Вайтран, простое железо" },
  { id: "gutter", label: "Тень обочины", note: "Рифтен, отмычка" },
  { id: "acolyte", label: "Послушник", note: "Виндхельм, храмовая ряса" },
]

export function CreateHeroPage() {
  const [name, setName] = useState("")
  const [race, setRace] = useState("Норд")
  const [heroClass, setHeroClass] = useState("Воин")
  const [origin, setOrigin] = useState("beggar")
  const [dossier, setDossier] = useState("")
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")
  const setHero = useGameStore((s) => s.setHero)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")
    setLoading(true)
    try {
      const hero = await api.createHero(name, race, heroClass, origin, dossier)
      setHero(hero)
    } catch (err: any) {
      setError(err.message || "Ошибка создания героя")
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="dashboard observatory" style={{ minHeight: "100vh" }}>
      <div style={{ width: 480, maxWidth: "90vw" }} className="anim-fade-up">
        <div style={{ textAlign: "center", marginBottom: "var(--space-8)" }}>
          <h1 style={{ fontFamily: "var(--font-display)", fontSize: "var(--text-2xl)", fontWeight: 800, letterSpacing: "-0.02em", marginBottom: "var(--space-2)" }}>Создание героя</h1>
          <p style={{ color: "var(--muted)", fontSize: "var(--text-sm)" }}>Выбери имя, расу и класс</p>
        </div>

        <div className="panel">
          <div className="panel-body" style={{ padding: "var(--space-4)" }}>
            <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
              <div>
                <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 4, display: "block" }}>Имя</label>
                <input type="text" value={name} onChange={(e) => setName(e.target.value)} required maxLength={30} placeholder="Дракенфел"
                  style={{ width: "100%", padding: "var(--space-2) var(--space-3)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)", outline: "none" }} />
              </div>

              <div>
                <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 8, display: "block" }}>Раса</label>
                <div style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: "var(--space-1)" }}>
                  {races.map((r) => (
                    <button key={r} type="button" onClick={() => setRace(r)}
                      style={{ padding: "6px 8px", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", fontWeight: 500, border: "none", cursor: "pointer", transition: "all 150ms",
                        background: race === r ? "var(--accent)" : "var(--panel-bg)", color: race === r ? "var(--accent-on)" : "var(--muted)" }}>
                      {r}
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 8, display: "block" }}>Класс</label>
                <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: "var(--space-1)" }}>
                  {classes.map((c) => (
                    <button key={c} type="button" onClick={() => setHeroClass(c)}
                      style={{ padding: "6px 8px", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", fontWeight: 500, border: "none", cursor: "pointer", transition: "all 150ms",
                        background: heroClass === c ? "var(--accent)" : "var(--panel-bg)", color: heroClass === c ? "var(--accent-on)" : "var(--muted)" }}>
                      {c}
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 8, display: "block" }}>Предыстория</label>
                <div style={{ display: "grid", gap: 6 }}>
                  {origins.map((o) => (
                    <button key={o.id} type="button" onClick={() => setOrigin(o.id)}
                      style={{ textAlign: "left", padding: "8px 10px", borderRadius: "var(--radius-md)", border: "1px solid var(--border)", cursor: "pointer",
                        background: origin === o.id ? "var(--accent)" : "var(--panel-bg)", color: origin === o.id ? "var(--accent-on)" : "var(--fg)" }}>
                      <b style={{ fontSize: "var(--text-sm)" }}>{o.label}</b>
                      <span style={{ display: "block", fontSize: "var(--text-xs)", opacity: .75 }}>{o.note}</span>
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 4, display: "block" }}>О герое · необязательно</label>
                <textarea value={dossier} maxLength={500} onChange={(e) => setDossier(e.target.value)} placeholder="На решения не влияет"
                  style={{ width: "100%", minHeight: 72, padding: "var(--space-2) var(--space-3)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)", resize: "vertical" }} />
              </div>

              {error && <div style={{ color: "var(--danger)", fontSize: "var(--text-sm)", textAlign: "center" }}>{error}</div>}

              <button type="submit" disabled={loading || !name.trim()}
                style={{ width: "100%", padding: "var(--space-2) var(--space-4)", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontWeight: 600, fontSize: "var(--text-sm)", border: "none", cursor: "pointer", opacity: loading || !name.trim() ? 0.5 : 1 }}>
                {loading ? "Создание…" : "Создать героя"}
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
  )
}

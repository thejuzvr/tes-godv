import { useState } from "react"
import { api } from "@/lib/api"
import { useGameStore } from "@/stores/gameStore"

const races = ["Норд", "Имперец", "Бретонец", "Редгард", "Альтмер", "Босмер", "Данмер", "Орк", "Каджит", "Аргонианин"]
const classes = ["Воин", "Маг", "Вор", "Разбойник", "Охотник", "Жрец", "Паладин", "Ассасин"]

export function CreateHeroPage() {
  const [name, setName] = useState("")
  const [race, setRace] = useState("Норд")
  const [heroClass, setHeroClass] = useState("Воин")
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState("")
  const setHero = useGameStore((s) => s.setHero)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")
    setLoading(true)
    try {
      const hero = await api.createHero(name, race, heroClass)
      setHero(hero)
    } catch (err: any) {
      setError(err.message || "Ошибка создания героя")
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center", background: "var(--bg)" }}>
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

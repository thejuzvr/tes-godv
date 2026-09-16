import { useEffect, useState } from "react"
import type { Pet } from "@/stores/gameStore"

const SPECIES: Record<string, { icon: string; name: string }> = {
  wolf: { icon: "🐺", name: "Волк" },
  owl: { icon: "🦉", name: "Сова" },
  cat: { icon: "🐈", name: "Кот" },
  lizard: { icon: "🦎", name: "Ящерица" },
}

const BONUS: Record<string, string> = {
  wolf: "Помогает в бою (урон по лояльности)",
  owl: "Замечает интересное при исследованиях",
  cat: "Поднимает настроение хозяину",
  lizard: "Компаньон для тихих дел",
}

function Bar({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8, fontSize: "var(--text-xs)" }}>
      <span style={{ color: "var(--muted)", width: 58 }}>{label}</span>
      <div style={{ flex: 1, height: 6, background: "var(--bg-elevated)", borderRadius: 3, overflow: "hidden" }}>
        <div style={{ height: "100%", width: `${value}%`, background: color, borderRadius: 3 }} />
      </div>
      <span style={{ fontFamily: "var(--font-mono)", color: "var(--fg)", width: 30, textAlign: "right" }}>{Math.round(value)}</span>
    </div>
  )
}

function Countdown({ reviveAt }: { reviveAt: string }) {
  const [left, setLeft] = useState("")

  useEffect(() => {
    const tick = () => {
      const ms = new Date(reviveAt).getTime() - Date.now()
      if (ms <= 0) { setLeft("скоро вернётся"); return }
      const h = Math.floor(ms / 3600000)
      const m = Math.floor((ms % 3600000) / 60000)
      const s = Math.floor((ms % 60000) / 1000)
      setLeft(h > 0 ? `${h}ч ${m}м` : m > 0 ? `${m}м ${s}с` : `${s}с`)
    }
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [reviveAt])

  return <span style={{ fontFamily: "var(--font-mono)" }}>{left}</span>
}

export function PetCard({ pets }: { pets?: Pet[] }) {
  if (!pets || pets.length === 0) {
    return (
      <div className="panel">
        <div className="panel-header">
          <div className="flex items-center gap-2">
            <span className="panel-icon">🐾</span>
            Питомец
          </div>
        </div>
        <div className="panel-body" style={{ textAlign: "center", color: "var(--muted)", padding: "var(--space-4)" }}>
          Пока никого. Герой может приютить зверя в таверне.
        </div>
      </div>
    )
  }

  return (
    <>
      {pets.map((pet) => {
        const sp = SPECIES[pet.species] || { icon: "🐾", name: pet.species }
        const isCooldown = pet.status === "cooldown"
        const isGone = pet.status === "gone"

        return (
          <div key={pet.id} className="panel">
            <div className="panel-header">
              <div className="flex items-center gap-2">
                <span className="panel-icon">{sp.icon}</span>
                {sp.name} · {pet.name}
                <span
                  style={{
                    marginLeft: "auto",
                    fontSize: "var(--text-xs)",
                    padding: "2px 8px",
                    borderRadius: "var(--radius-pill)",
                    border: "1px solid var(--border)",
                    color: isGone ? "var(--danger)" : isCooldown ? "var(--warn)" : "var(--success)",
                  }}
                >
                  {isGone ? "ушёл · в истории" : isCooldown ? "ранен" : "рядом"}
                </span>
              </div>
            </div>
            <div className="panel-body">
              {isGone ? (
                <div style={{ color: "var(--muted)", fontSize: "var(--text-sm)", textAlign: "center", padding: "var(--space-2)" }}>
                  Лояльность упала до нуля — питомец ушёл в лес. Когда у героя появится новый зверь, этот уйдёт со страницы (останется в Аналитике).
                </div>
              ) : isCooldown ? (
                <div style={{ textAlign: "center", padding: "var(--space-2)" }}>
                  <div style={{ fontSize: 28, marginBottom: 4 }}>{sp.icon}</div>
                  <div style={{ fontSize: "var(--text-sm)", color: "var(--muted)" }}>
                    Питомец получил тяжёлые раны в бою и лечится.
                  </div>
                  <div style={{ fontSize: "var(--text-base)", fontWeight: 600, marginTop: 4 }}>
                    Вернётся через <Countdown reviveAt={pet.revive_at || ""} />
                  </div>
                </div>
              ) : (
                <>
                  <div style={{ display: "flex", gap: "var(--space-3)", alignItems: "center", marginBottom: "var(--space-2)" }}>
                    <div style={{ fontSize: 30 }}>{sp.icon}</div>
                    <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>{BONUS[pet.species]}</div>
                  </div>
                  <div style={{ display: "flex", flexDirection: "column", gap: 5 }}>
                    <Bar label="Настроение" value={pet.mood} color="var(--xp)" />
                    <Bar label="Сытость" value={100 - pet.hunger} color={pet.hunger > 80 ? "var(--danger)" : "var(--success)"} />
                    <Bar label="Лояльность" value={pet.loyalty} color={pet.loyalty < 20 ? "var(--danger)" : "var(--mp)"} />
                  </div>
                  {pet.loyalty < 20 && (
                    <div style={{ marginTop: "var(--space-2)", fontSize: "var(--text-xs)", color: "var(--warn)" }}>
                      ⚠️ Питомец почти готов уйти — нужен уход!
                    </div>
                  )}
                </>
              )}
            </div>
          </div>
        )
      })}
    </>
  )
}

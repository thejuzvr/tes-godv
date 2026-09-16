import { useState, useEffect, useCallback } from "react"
import { api } from "@/lib/api"

interface EquipmentItem {
  id: string
  name: string
  icon: string
  rarity: string
  attack_bonus: number
  defense_bonus: number
  hp_bonus: number
  sharpen_level: number
  sharpen_cap: number
  next_sharpen_cost: number | null
}

const SLOT_CONFIG = [
  { key: "weapon", label: "Оружие", icon: "⚔️" },
  { key: "head", label: "Голова", icon: "🪖" },
  { key: "body", label: "Броня", icon: "🛡️" },
  { key: "legs", label: "Ноги", icon: "👢" },
  { key: "ring", label: "Кольцо", icon: "💍" },
  { key: "amulet", label: "Амулет", icon: "📿" },
]

const rarityColors: Record<string, string> = {
  common: "var(--muted)",
  uncommon: "var(--success)",
  rare: "var(--mp)",
  epic: "var(--epic)",
  legendary: "var(--gold)",
}

const rarityLabels: Record<string, string> = {
  common: "Обычный",
  uncommon: "Необычный",
  rare: "Редкий",
  epic: "Эпический",
  legendary: "Легендарный",
}

export function EquipmentPanel({ refreshTrigger, headless = false }: { refreshTrigger?: number; headless?: boolean }) {
  const [equipment, setEquipment] = useState<Record<string, EquipmentItem | null>>({})
  const [heroGold, setHeroGold] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)

  const loadEquipment = useCallback(() => {
    api.getEquipment()
      .then((data) => {
        setEquipment(data.slots ?? {})
        setHeroGold(data.hero_gold ?? null)
      })
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [])

  useEffect(() => {
    loadEquipment()
  }, [loadEquipment, refreshTrigger])

  const unequip = async (slot: string, label: string) => {
    if (busy) return
    setBusy(true)
    setNotice(null)
    try {
      await api.unequipItem(slot)
      setNotice(`${label}: снято`)
      loadEquipment()
    } catch (e: any) {
      setNotice(e?.message || "Не получилось снять")
    } finally {
      setBusy(false)
    }
  }

  // C-2 Небесная кузня: заточка
  const enhance = async (slot: string) => {
    if (busy) return
    setBusy(true)
    setNotice(null)
    try {
      const res = await api.enhanceEquipment(slot)
      setNotice(`«${res.item.name}» заточено до +${res.level}. Осталось ${res.gold_left.toLocaleString("ru-RU")} 🪙`)
      loadEquipment()
      window.dispatchEvent(new CustomEvent("tes:hero-refresh"))
    } catch (e: any) {
      const msg = e?.message || String(e)
      setNotice(
        msg.includes("cap_reached") ? "Небесная кузня выковала предел для этой вещи."
        : msg.includes("not_enough_gold") ? "Не хватает золота для заточки."
        : "Кузня не приняла заказ.",
      )
    } finally {
      setBusy(false)
    }
  }

  if (loading) {
    if (headless) return <div style={{ padding: 16, color: "var(--muted)", fontSize: "var(--text-sm)" }}>Загрузка снаряжения…</div>
    return (
      <div className="panel fantasy-window">
        <div className="panel-header">
          <div className="flex items-center gap-2">
            <span className="panel-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>
            </span>
            Снаряжение
          </div>
        </div>
        <div className="panel-body"><span style={{ color: "var(--muted)", fontSize: "var(--text-sm)" }}>Загрузка…</span></div>
      </div>
    )
  }

  const totalAttack = Object.values(equipment).reduce((sum, item) => sum + (item?.attack_bonus || 0), 0)
  const totalDefense = Object.values(equipment).reduce((sum, item) => sum + (item?.defense_bonus || 0), 0)
  const totalHp = Object.values(equipment).reduce((sum, item) => sum + (item?.hp_bonus || 0), 0)

  const content = (
    <div className="equipment-body" style={{ padding: 0 }}>
      {/* Notice */}
      {notice && (
        <div style={{ padding: "6px 12px", background: "color-mix(in srgb, var(--accent) 15%, transparent)", borderBottom: "1px solid var(--border)", fontSize: "var(--text-xs)", color: "var(--accent)" }}>
          {notice}
        </div>
      )}
        {/* Total bonuses */}
        {(totalAttack > 0 || totalDefense > 0 || totalHp > 0) && (
          <div style={{ padding: "var(--space-2) var(--space-3)", borderBottom: "1px solid var(--border)", display: "flex", gap: "var(--space-3)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)" }}>
            {totalAttack > 0 && <span style={{ color: "var(--danger)" }}>⚔️ +{totalAttack}</span>}
            {totalDefense > 0 && <span style={{ color: "var(--mp)" }}>🛡️ +{totalDefense}</span>}
            {totalHp > 0 && <span style={{ color: "var(--success)" }}>❤️ +{totalHp}</span>}
          </div>
        )}

        {/* Slots */}
        {SLOT_CONFIG.map(slot => {
          const item = equipment[slot.key]
          const isEmpty = !item
          return (
            <div key={slot.key} style={{
              display: "flex", alignItems: "center", gap: "var(--space-3)",
              padding: "var(--space-2) var(--space-3)",
              borderBottom: "1px solid var(--border)",
              opacity: isEmpty ? 0.5 : 1,
            }}>
              <span style={{ fontSize: 18, width: 28, textAlign: "center", flexShrink: 0 }}>{item?.icon || slot.icon}</span>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: "var(--text-sm)", fontWeight: 500, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  {item?.name || slot.label}
                </div>
                <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontFamily: "var(--font-mono)", display: "flex", gap: "var(--space-2)" }}>
                  {item?.attack_bonus ? <span style={{ color: "var(--danger)" }}>⚔️+{item.attack_bonus}</span> : null}
                  {item?.defense_bonus ? <span style={{ color: "var(--mp)" }}>🛡️+{item.defense_bonus}</span> : null}
                  {item?.hp_bonus ? <span style={{ color: "var(--success)" }}>❤️+{item.hp_bonus}</span> : null}
                </div>
              </div>
              {item && (
                <span style={{
                  fontSize: 10, fontFamily: "var(--font-mono)", padding: "2px 6px",
                  borderRadius: "var(--radius-pill)", whiteSpace: "nowrap",
                  color: rarityColors[item.rarity] || "var(--muted)",
                  background: `color-mix(in oklab, ${rarityColors[item.rarity] || "var(--muted)"}, transparent 85%)`,
                }}>
                  {rarityLabels[item.rarity] || item.rarity}
                </span>
              )}
              {item && item.sharpen_level > 0 && (
                <span style={{ fontSize: 10, fontFamily: "var(--font-mono)", color: "var(--gold)", whiteSpace: "nowrap" }}>
                  ⚒+{item.sharpen_level}
                </span>
              )}
              {item && (
                <button
                  onClick={() => enhance(slot.key)}
                  disabled={busy || item.next_sharpen_cost === null || (heroGold !== null && heroGold < item.next_sharpen_cost)}
                  aria-label={`Заточить ${item.name}${item.next_sharpen_cost !== null ? ` за ${item.next_sharpen_cost} золота` : ""}`}
                  style={{
                    fontSize: 11, padding: "3px 8px", flexShrink: 0,
                    border: "1px solid var(--border)", borderRadius: "var(--radius-sm)",
                    background: "transparent",
                    color: item.next_sharpen_cost !== null && (heroGold === null || heroGold >= item.next_sharpen_cost) ? "var(--gold)" : "var(--muted)",
                    cursor: busy ? "wait" : item.next_sharpen_cost === null ? "default" : "pointer",
                    opacity: busy || item.next_sharpen_cost === null ? 0.5 : 1,
                    transition: "opacity 0.2s, border-color 0.2s",
                    whiteSpace: "nowrap",
                  }}
                >
                  {item.next_sharpen_cost === null ? "⚒ предел" : `⚒ ${item.next_sharpen_cost}🪙`}
                </button>
              )}
              {item && (
                <button
                  onClick={() => unequip(slot.key, item.name)}
                  disabled={busy}
                  aria-label={`Снять ${item.name}`}
                  style={{
                    fontSize: 11, padding: "3px 8px", flexShrink: 0,
                    border: "1px solid var(--border)", borderRadius: "var(--radius-sm)",
                    background: "transparent", color: "var(--muted)", cursor: busy ? "wait" : "pointer",
                    opacity: busy ? 0.5 : 1, transition: "opacity 0.2s",
                  }}
                >
                  Снять
                </button>
              )}
            </div>
          )
        })}
      </div>
    )

    if (headless) {
      return content
    }

    return (
      <div className="panel fantasy-window">
        <div className="panel-header">
          <div className="flex items-center gap-2">
            <span className="panel-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>
            </span>
            Снаряжение
          </div>
        </div>
        {content}
      </div>
    )
  }

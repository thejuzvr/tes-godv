import { useEffect, useState } from "react"
import { api } from "@/lib/api"
import { formatNumber } from "@/lib/utils"

/* ─── Inventory Panel — именованные слоты, редкость, детали, действия ─── */

const RARITY: Record<string, { label: string; color: string }> = {
  common: { label: "Обычный", color: "var(--muted)" },
  uncommon: { label: "Необычный", color: "var(--success)" },
  rare: { label: "Редкий", color: "var(--mp)" },
  epic: { label: "Эпический", color: "var(--epic)" },
  legendary: { label: "Легендарный", color: "var(--gold)" },
}

const TYPE_RU: Record<string, string> = {
  consumable: "Расходник",
  equipment: "Снаряжение",
  material: "Материал",
  misc: "Разное",
  quest: "Квестовый",
}

export function InventoryPanel({ refreshTrigger = 0, headless = false }: { refreshTrigger?: number; headless?: boolean }) {
  const [data, setData] = useState<{ items: any[]; weight: any } | null>(null)
  const [failed, setFailed] = useState(false)
  const [selected, setSelected] = useState<any>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [equipTick, setEquipTick] = useState(0)

  useEffect(() => {
    setFailed(false)
    api.getInventory().then(setData).catch(() => setFailed(true))
  }, [refreshTrigger])

  const refetch = () => api.getInventory().then(setData).catch(() => {})

  const act = async (kind: "use" | "drop" | "equip") => {
    if (!selected || busy) return
    setBusy(true)
    setNotice(null)
    try {
      const res =
        kind === "use" ? await api.useItem(selected.item_id) :
        kind === "equip" ? await api.equipItem(selected.item_id) :
        await api.dropItem(selected.item_id)
      const raw: string = res?.message || "Готово"
      setNotice(raw
        .replace(/^Used\s+/, "Использовано: ")
        .replace(/^Dropped\s+/, "Выброшено: ")
        .replace(/^Equipped\s+(.+)\s+in\s+(.+)$/, "Надето: $1 ($2)"))
      await refetch()
      // Экипировка меняет бонусы и инвентарь — обновляем панели через их refreshTrigger
      window.dispatchEvent(new CustomEvent("tes:hero-refresh"))
      setEquipTick((t) => t + 1)
      if (kind !== "equip") setSelected(null)
    } catch (e: any) {
      setNotice(e?.message || "Не получилось")
    } finally {
      setBusy(false)
    }
  }

  const body = (
    <div className="inventory-content">
      {failed ? (
        <span style={{ color: "var(--muted)", fontSize: "var(--text-sm)" }}>Инвентарь недоступен — обнови страницу.</span>
      ) : !data ? (
        <span style={{ color: "var(--muted)", fontSize: "var(--text-sm)" }}>Загрузка…</span>
      ) : (
        <>
          <WeightBar weight={data.weight} />
          <div className="inv-grid">
            {padSlots(data.items).map((s, i) =>
              s ? (
                <button
                  key={i}
                  className={`inv-slot named ${selected?.item_id === s.item_id ? "selected" : ""} rarity-${s.rarity || "common"}`}
                  onClick={() => setSelected(selected?.item_id === s.item_id ? null : s)}
                  title={s.name}
                >
                  <span className="inv-icon">{s.icon}</span>
                  {s.quantity > 1 && <span className="inv-count">{s.quantity}</span>}
                  <span className="inv-name">{s.name}</span>
                </button>
              ) : (
                <div key={i} className="inv-slot empty"><span className="inv-icon">·</span></div>
              )
            )}
          </div>
          {selected && <ItemDetail key={equipTick} item={selected} busy={busy} onUse={() => act("use")} onDrop={() => act("drop")} onEquip={() => act("equip")} />}
          {notice && (
            <div style={{ marginTop: "var(--space-2)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--success)" }}>{notice}</div>
          )}
        </>
      )}
    </div>
  )

  if (headless) {
    return <div style={{ padding: "var(--space-3)" }}>{body}</div>
  }

  return (
    <div className="panel fantasy-window">
      <div className="panel-header">
        <div className="flex items-center gap-2">
          <span className="panel-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/></svg>
          </span>
          Инвентарь
          {data && <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--muted)", fontWeight: 400, textTransform: "none", letterSpacing: 0 }}>{data.items.length} / 16</span>}
        </div>
      </div>
      <div className="panel-body">
        {body}
      </div>
    </div>
  )
}

function padSlots(items: any[]): (any | null)[] {
  const slots: (any | null)[] = [...items]
  while (slots.length < 16) slots.push(null)
  return slots
}

function WeightBar({ weight }: { weight: any }) {
  const weightColor = weight.heavily_overweight ? "var(--danger)" : weight.overweight ? "var(--warn)" : "var(--success)"
  return (
    <div style={{ marginBottom: "var(--space-3)" }}>
      <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "var(--space-1)" }}>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.04em" }}>Вес</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: weightColor, fontWeight: 600 }}>{weight.current} / {weight.max}</span>
      </div>
      <div style={{ height: 4, background: "color-mix(in oklab, var(--fg), transparent 92%)", borderRadius: 2, overflow: "hidden" }}>
        <div style={{ height: "100%", width: `${Math.min(weight.percentage, 100)}%`, background: weightColor, borderRadius: 2, transition: "width 0.3s" }} />
      </div>
      {weight.overweight && (
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: weightColor, marginTop: 4, display: "block" }}>
          {weight.heavily_overweight ? "Перегруз! Герой едва тащит сумку" : "Перегруз — герой двигается медленнее"}
        </span>
      )}
    </div>
  )
}

function ItemDetail({ item, busy, onUse, onDrop, onEquip }: { item: any; busy: boolean; onUse: () => void; onDrop: () => void; onEquip: () => void }) {
  const rarity = RARITY[item.rarity] || RARITY.common
  return (
    <div style={{ marginTop: "var(--space-3)", padding: "var(--space-3)", background: "var(--bg-elevated)", borderRadius: "var(--radius-md)", border: `1px solid color-mix(in oklab, ${rarity.color}, transparent 60%)` }}>
      <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", marginBottom: 6 }}>
        <span style={{ fontSize: 16 }}>{item.icon}</span>
        <span style={{ fontSize: "var(--text-sm)", fontWeight: 600, flex: 1 }}>{item.name}</span>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 10, textTransform: "uppercase", letterSpacing: "0.05em", color: rarity.color, border: `1px solid color-mix(in oklab, ${rarity.color}, transparent 55%)`, padding: "1px 8px", borderRadius: "var(--radius-pill)" }}>{rarity.label}</span>
      </div>
      <div style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--muted)", display: "flex", gap: "var(--space-3)", marginBottom: "var(--space-2)" }}>
        <span>{TYPE_RU[item.type] || item.type}</span>
        <span>{item.weight} вес</span>
        <span>{formatNumber(item.sell_price || 0)} золота</span>
        {item.quantity > 1 && <span>×{item.quantity}</span>}
      </div>
      <div style={{ display: "flex", gap: "var(--space-2)" }}>
        {item.type === "consumable" && (
          <button onClick={onUse} disabled={busy} style={{ flex: 1, padding: "6px 0", fontSize: "var(--text-xs)", fontWeight: 600, background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-sm)", opacity: busy ? 0.5 : 1 }}>
            Использовать
          </button>
        )}
        {item.type === "equipment" && (
          <button onClick={onEquip} disabled={busy} style={{ flex: 1, padding: "6px 0", fontSize: "var(--text-xs)", fontWeight: 600, background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-sm)", opacity: busy ? 0.5 : 1 }}>
            Надеть
          </button>
        )}
        <button onClick={onDrop} disabled={busy} style={{ flex: 1, padding: "6px 0", fontSize: "var(--text-xs)", fontWeight: 500, border: "1px solid var(--border)", color: "var(--muted)", borderRadius: "var(--radius-sm)", background: "transparent", opacity: busy ? 0.5 : 1 }}>
          Выбросить
        </button>
      </div>
    </div>
  )
}

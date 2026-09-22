import { Component, useEffect, useState, type ReactNode } from "react"
import { EquipmentPanel } from "@/components/hero/EquipmentPanel"
import { InventoryPanel } from "@/components/game/InventoryPanel"

/* Снаряжение и сумка рядом. После действия обе половины обновляются сразу:
   предмет не должен пропадать, пока не обновишь вторую. */
export function GearPage() {
  return (
    <GearBoundary>
      <GearBody />
    </GearBoundary>
  )
}

class GearBoundary extends Component<{ children: ReactNode }, { error: string | null }> {
  state = { error: null as string | null }
  static getDerivedStateFromError(error: Error) { return { error: error.message } }
  render() {
    if (this.state.error) return <p className="character-note" role="alert">Снаряжение не открылось: {this.state.error}</p>
    return this.props.children
  }
}

function GearBody() {
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const refresh = () => setTick((n) => n + 1)
    window.addEventListener("tes:hero-refresh", refresh)
    return () => window.removeEventListener("tes:hero-refresh", refresh)
  }, [])

  return (
    <div className="character-stack">
      <header className="character-head">
        <p>Снаряжение</p>
        <h1>Что при нём</h1>
      </header>
      <div className="character-gear">
        <EquipmentPanel refreshTrigger={tick} />
        <InventoryPanel refreshTrigger={tick} />
      </div>
    </div>
  )
}

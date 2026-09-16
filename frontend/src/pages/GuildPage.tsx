import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import {
  Shield,
  Flame,
  ShoppingBag,
  Users,
  MessageSquare,
  Search,
  LogOut,
  Check,
  X,
  Sparkles,
  Beer,
  Crown,
  Swords,
  UserCheck,
  Send,
  AlertCircle,
  Scroll,
  Plus,
} from "lucide-react"
import { api } from "@/lib/api"
import { useGameStore } from "@/stores/gameStore"
import {
  GUILD_EMBLEMS,
  GUILD_POLICY_RU,
  GUILD_ROLE_RU,
  type GuildChatMessage,
  type GuildDetail,
  type GuildSummary,
  type GuildMemberRow,
} from "@/stores/guildStore"
import "./guild-skin.css"

const CREATE_COST = 500

function fmt(n?: number): string {
  return (n || 0).toLocaleString("ru-RU")
}

function fmtTime(iso?: string): string {
  if (!iso) return ""
  try {
    const d = new Date(iso.endsWith("Z") || iso.includes("+") ? iso : `${iso}Z`)
    return d.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" })
  } catch {
    return ""
  }
}

function fmtDate(iso?: string): string {
  if (!iso) return ""
  try {
    const d = new Date(iso.endsWith("Z") || iso.includes("+") ? iso : `${iso}Z`)
    return d.toLocaleDateString("ru-RU", { day: "numeric", month: "short" })
  } catch {
    return ""
  }
}

// ── Модальное окно подтверждения выхода / роспуска ───────────────────────────
function LeaveConfirmModal({
  isLeader,
  onConfirm,
  onCancel,
  busy,
}: {
  isLeader: boolean
  onConfirm: () => void
  onCancel: () => void
  busy: boolean
}) {
  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        backgroundColor: "rgba(0, 0, 0, 0.7)",
        backdropFilter: "blur(4px)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        zIndex: 9999,
        padding: 16,
      }}
      role="dialog"
      aria-modal="true"
      aria-labelledby="leave-modal-title"
    >
      <div
        className="fantasy-window"
        style={{
          maxWidth: 480,
          width: "100%",
          padding: "26px 30px",
          background: "var(--surface)",
          borderColor: "var(--danger)",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10, color: "var(--danger)", marginBottom: 12 }}>
          <AlertCircle size={22} />
          <h3 id="leave-modal-title" style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: 0, color: "var(--fg)" }}>
            {isLeader ? "Сложить знамя гильдии?" : "Покинуть ряды соратников?"}
          </h3>
        </div>
        <p style={{ fontSize: "var(--text-sm)", color: "var(--muted)", lineHeight: 1.55, marginBottom: 22 }}>
          {isLeader
            ? "Если в гильдии есть соратники, знамя перейдёт старшему офицеру или самому преданному воину. Если ты один — гильдия будет распущена навсегда."
            : "Ты утратишь доступ к общему алтарю, казне и лавке соратников. Вступить снова можно будет в любое время."}
        </p>
        <div style={{ display: "flex", justifyContent: "flex-end", gap: 12 }}>
          <button
            onClick={onCancel}
            disabled={busy}
            style={{
              padding: "9px 18px",
              borderRadius: "var(--radius-sm)",
              border: "1px solid var(--border)",
              color: "var(--fg)",
              fontSize: "var(--text-xs)",
              background: "var(--surface-raised)",
              cursor: "pointer",
            }}
          >
            Остаться
          </button>
          <button
            onClick={onConfirm}
            disabled={busy}
            style={{
              padding: "9px 20px",
              borderRadius: "var(--radius-sm)",
              background: "var(--danger)",
              color: "#fff",
              fontWeight: 600,
              fontSize: "var(--text-xs)",
              cursor: busy ? "default" : "pointer",
              opacity: busy ? 0.6 : 1,
              border: "none",
            }}
          >
            {busy ? "Выход…" : isLeader ? "Передать знамя и уйти" : "Покинуть гильдию"}
          </button>
        </div>
      </div>
    </div>
  )
}

// ── Имперская хартия создания гильдии (просторный 2-колоночный формуляр) ────
function CreateGuildCharter({
  heroGold,
  onCreated,
  onCancel,
}: {
  heroGold: number
  onCreated: () => void
  onCancel: () => void
}) {
  const [name, setName] = useState("")
  const [motto, setMotto] = useState("")
  const [emblem, setEmblem] = useState<string>(GUILD_EMBLEMS[0])
  const [policy, setPolicy] = useState("open")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const canAfford = heroGold >= CREATE_COST

  const submit = async () => {
    if (busy || name.trim().length < 3 || !canAfford) return
    setBusy(true)
    setError(null)
    try {
      await api.createGuild({ name: name.trim(), motto: motto.trim() || undefined, emblem, policy })
      onCreated()
    } catch (e: any) {
      const msg = e?.message || String(e)
      if (msg.includes("already_in_guild")) setError("Ты уже состоишь в гильдии.")
      else if (msg.includes("not_enough_gold")) setError(`Нужно ${CREATE_COST} золота на учредительный взнос.`)
      else if (msg.includes("has already been taken") || msg.includes("unique")) setError("Такое название уже занято.")
      else if (msg.includes("is too short")) setError("Название: от 3 до 24 символов.")
      else setError("Не удалось учредить гильдию, проверь правильность полей.")
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="imperial-charter-modal anim-fade-up" style={{ width: "100%", maxWidth: 1040, margin: "0 auto 28px" }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <span style={{ fontSize: 32 }}>📜</span>
          <div>
            <h2 style={{ fontFamily: "var(--font-display)", fontSize: 24, fontWeight: 800, color: "var(--fg)", margin: 0 }}>
              Имперская хартия нового знамени
            </h2>
            <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)", marginTop: 2 }}>
              Учредительный взнос: <strong style={{ color: "var(--gold)" }}>{CREATE_COST} 🪙</strong> поступает в фонд Девяти
            </div>
          </div>
        </div>
        <button
          onClick={onCancel}
          style={{ padding: 8, color: "var(--muted)", borderRadius: "var(--radius-sm)", cursor: "pointer" }}
          aria-label="Закрыть"
        >
          <X size={20} />
        </button>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))", gap: 24, alignItems: "start" }}>
        {/* Живой предпросмотр знамени */}
        <div
          style={{
            background: "var(--surface-raised)",
            border: "1px dashed color-mix(in oklab, var(--border), var(--accent) 40%)",
            borderRadius: "var(--radius-md)",
            padding: "24px 22px",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            textAlign: "center",
            gap: 14,
          }}
        >
          <div className="guild-emblem-crest" style={{ width: 88, height: 88, fontSize: 46 }}>
            {emblem}
          </div>
          <div>
            <div style={{ fontFamily: "var(--font-display)", fontSize: 22, fontWeight: 800, color: "var(--fg)" }}>
              {name.trim() || "Название знамени"}
            </div>
            <div style={{ fontFamily: "var(--font-display)", fontStyle: "italic", fontSize: 14, color: "var(--accent)", marginTop: 4 }}>
              {motto.trim() ? `«${motto.trim()}»` : "«Девиз братства…»"}
            </div>
            <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 8, fontFamily: "var(--font-mono)" }}>
              Ранг 1 · 1 соратник · {GUILD_POLICY_RU[policy] || policy}
            </div>
          </div>

          <div
            style={{
              width: "100%",
              marginTop: "auto",
              padding: "10px 14px",
              background: "var(--surface)",
              border: "1px solid var(--border)",
              borderRadius: "var(--radius-sm)",
              fontSize: 12,
              display: "flex",
              justifyContent: "space-between",
            }}
          >
            <span style={{ color: "var(--muted)" }}>В твоём кошельке:</span>
            <span style={{ fontFamily: "var(--font-mono)", color: canAfford ? "var(--gold)" : "var(--danger)", fontWeight: 600 }}>
              {fmt(heroGold)} / {CREATE_COST} 🪙 {!canAfford && `(нужно ещё ${fmt(CREATE_COST - heroGold)} 🪙)`}
            </span>
          </div>
        </div>

        {/* Поля ввода хартии */}
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div>
            <label style={{ display: "block", fontSize: "var(--text-xs)", color: "var(--muted)", marginBottom: 6 }}>
              Название знамени (от 3 до 24 знаков)
            </label>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              maxLength={24}
              placeholder="Например: Соратники Вайтрана"
              style={{
                width: "100%",
                padding: "10px 14px",
                background: "var(--bg-elevated)",
                border: "1px solid var(--border)",
                borderRadius: "var(--radius-sm)",
                color: "var(--fg)",
                fontSize: "var(--text-sm)",
              }}
            />
          </div>

          <div>
            <label style={{ display: "block", fontSize: "var(--text-xs)", color: "var(--muted)", marginBottom: 6 }}>
              Девиз гильдии (до 80 знаков)
            </label>
            <input
              value={motto}
              onChange={(e) => setMotto(e.target.value)}
              maxLength={80}
              placeholder="Например: Честь в битве, верность в братстве"
              style={{
                width: "100%",
                padding: "10px 14px",
                background: "var(--bg-elevated)",
                border: "1px solid var(--border)",
                borderRadius: "var(--radius-sm)",
                color: "var(--fg)",
                fontSize: "var(--text-sm)",
              }}
            />
          </div>

          <div>
            <label style={{ display: "block", fontSize: "var(--text-xs)", color: "var(--muted)", marginBottom: 8 }}>
              Геральдическая эмблема
            </label>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }} role="radiogroup" aria-label="Выбор эмблемы">
              {GUILD_EMBLEMS.map((e) => {
                const active = emblem === e
                return (
                  <button
                    key={e}
                    type="button"
                    onClick={() => setEmblem(e)}
                    role="radio"
                    aria-checked={active}
                    style={{
                      fontSize: 24,
                      padding: "8px 14px",
                      background: active ? "color-mix(in oklab, var(--accent), transparent 85%)" : "var(--surface-raised)",
                      border: `1px solid ${active ? "var(--accent)" : "var(--border)"}`,
                      borderRadius: "var(--radius-md)",
                      cursor: "pointer",
                      transform: active ? "scale(1.08)" : "scale(1)",
                      transition: "all 0.15s ease",
                    }}
                  >
                    {e}
                  </button>
                )
              })}
            </div>
          </div>

          <div>
            <label style={{ display: "block", fontSize: "var(--text-xs)", color: "var(--muted)", marginBottom: 8 }}>
              Политика приёма соратников
            </label>
            <div style={{ display: "flex", gap: 10 }}>
              {Object.entries(GUILD_POLICY_RU).map(([key, label]) => {
                const active = policy === key
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setPolicy(key)}
                    style={{
                      padding: "8px 16px",
                      fontSize: "var(--text-xs)",
                      fontWeight: active ? 600 : 400,
                      color: active ? "var(--accent)" : "var(--muted)",
                      background: active ? "color-mix(in oklab, var(--accent), transparent 85%)" : "var(--surface-raised)",
                      border: `1px solid ${active ? "var(--accent)" : "var(--border)"}`,
                      borderRadius: "var(--radius-sm)",
                      cursor: "pointer",
                      transition: "all 0.15s ease",
                    }}
                  >
                    {label}
                  </button>
                )
              })}
            </div>
          </div>

          {error && (
            <div
              role="alert"
              style={{
                padding: "8px 14px",
                background: "rgba(239, 68, 68, 0.12)",
                border: "1px solid rgba(239, 68, 68, 0.4)",
                borderRadius: "var(--radius-sm)",
                fontSize: "var(--text-xs)",
                color: "var(--danger)",
              }}
            >
              {error}
            </div>
          )}

          <div style={{ display: "flex", gap: 12, marginTop: 4 }}>
            <button
              type="button"
              onClick={submit}
              disabled={busy || name.trim().length < 3 || !canAfford}
              style={{
                flex: 1,
                padding: "12px 22px",
                background: canAfford ? "var(--accent)" : "var(--surface-raised)",
                color: canAfford ? "var(--accent-on)" : "var(--muted)",
                fontWeight: 700,
                fontSize: "var(--text-sm)",
                fontFamily: "var(--font-display)",
                letterSpacing: "0.02em",
                border: "none",
                borderRadius: "var(--radius-sm)",
                cursor: busy || name.trim().length < 3 || !canAfford ? "default" : "pointer",
                opacity: busy || name.trim().length < 3 || !canAfford ? 0.5 : 1,
                transition: "all 0.2s ease",
              }}
            >
              {busy ? "Учреждаем знамя…" : `Учредить знамя (${CREATE_COST} 🪙)`}
            </button>
            <button
              type="button"
              onClick={onCancel}
              style={{
                padding: "12px 20px",
                background: "transparent",
                color: "var(--muted)",
                border: "1px solid var(--border)",
                borderRadius: "var(--radius-sm)",
                fontSize: "var(--text-sm)",
                cursor: "pointer",
              }}
            >
              Отмена
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

// ── Экран выбора гильдии (полноширинный для 1080p) ────────────────────────────
function GuildLanding({
  guilds,
  heroGold,
  onJoin,
  onCreated,
}: {
  guilds: GuildSummary[]
  heroGold: number
  onJoin: (id: string) => Promise<boolean | "pending">
  onCreated: () => void
}) {
  const [creating, setCreating] = useState(false)
  const [search, setSearch] = useState("")
  const [policyFilter, setPolicyFilter] = useState<"all" | "open" | "request">("all")
  const [joiningId, setJoiningId] = useState<string | null>(null)
  const [notice, setNotice] = useState<{ type: "success" | "warn" | "error"; text: string } | null>(null)

  const handleJoin = async (id: string) => {
    if (joiningId) return
    setJoiningId(id)
    setNotice(null)
    const ok = await onJoin(id)
    if (ok === "pending") {
      setNotice({ type: "warn", text: "Прошение о вступлении подано совету офицеров." })
    } else if (ok === true) {
      setNotice({ type: "success", text: "Добро пожаловать под знамя!" })
    } else {
      setNotice({ type: "error", text: "Не удалось вступить — возможно, гильдия закрыта или произошла ошибка." })
    }
    setJoiningId(null)
  }

  const filteredGuilds = useMemo(() => {
    return guilds.filter((g) => {
      const matchSearch =
        search === "" ||
        g.name.toLowerCase().includes(search.toLowerCase()) ||
        (g.motto && g.motto.toLowerCase().includes(search.toLowerCase()))
      const matchPolicy =
        policyFilter === "all" ||
        (policyFilter === "open" && g.policy === "open") ||
        (policyFilter === "request" && g.policy === "request")
      return matchSearch && matchPolicy
    })
  }, [guilds, search, policyFilter])

  return (
    <div className="anim-fade-up" style={{ width: "100%", paddingBottom: 48 }}>
      {/* Презентационная шапка */}
      <div
        className="guild-bastion-banner"
        style={{
          marginBottom: 28,
          display: "flex",
          flexWrap: "wrap",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 24,
        }}
      >
        <div style={{ flex: 1, minWidth: 280 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, color: "var(--accent)", marginBottom: 6 }}>
            <Swords size={20} />
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, letterSpacing: "0.15em", textTransform: "uppercase", fontWeight: 700 }}>
              Союзы Тамриэля
            </span>
          </div>
          <h1 className="guild-title-hero">Оплоты и Ордены Скайрима</h1>
          <p style={{ color: "var(--muted)", fontSize: "var(--text-sm)", marginTop: 8, maxWidth: 720, lineHeight: 1.6 }}>
            Объединяйтесь под общими знамёнами, возводите подношения Священному Алтарю ради благословений опыта и атаки,
            закатывайте совместные пиры и приобретайте редкие реликвии в лавке соратников.
          </p>
        </div>

        {!creating && (
          <div>
            <button
              onClick={() => setCreating(true)}
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 8,
                padding: "13px 24px",
                background: "var(--accent)",
                color: "var(--accent-on)",
                fontWeight: 700,
                fontSize: "var(--text-sm)",
                fontFamily: "var(--font-display)",
                borderRadius: "var(--radius-sm)",
                cursor: "pointer",
                transition: "transform 0.2s ease",
              }}
            >
              <Plus size={18} />
              Учредить гильдию ({CREATE_COST} 🪙)
            </button>
            <div style={{ fontSize: 11, color: "var(--muted)", textAlign: "right", marginTop: 6, fontFamily: "var(--font-mono)" }}>
              В кошельке: {fmt(heroGold)} 🪙
            </div>
          </div>
        )}
      </div>

      {notice && (
        <div
          role="status"
          style={{
            padding: "12px 18px",
            borderRadius: "var(--radius-sm)",
            marginBottom: 24,
            fontSize: "var(--text-sm)",
            background:
              notice.type === "success"
                ? "rgba(34, 197, 94, 0.12)"
                : notice.type === "warn"
                  ? "rgba(234, 179, 8, 0.12)"
                  : "rgba(239, 68, 68, 0.12)",
            border: `1px solid ${
              notice.type === "success"
                ? "rgba(34, 197, 94, 0.35)"
                : notice.type === "warn"
                  ? "rgba(234, 179, 8, 0.35)"
                  : "rgba(239, 68, 68, 0.35)"
            }`,
            color:
              notice.type === "success"
                ? "var(--success)"
                : notice.type === "warn"
                  ? "var(--gold)"
                  : "var(--danger)",
          }}
        >
          {notice.text}
        </div>
      )}

      {creating ? (
        <CreateGuildCharter heroGold={heroGold} onCreated={onCreated} onCancel={() => setCreating(false)} />
      ) : (
        <>
          {/* Поиск и фильтрация */}
          <div
            style={{
              display: "flex",
              flexWrap: "wrap",
              alignItems: "center",
              justifyContent: "space-between",
              gap: 16,
              marginBottom: 24,
            }}
          >
            <div style={{ display: "flex", alignItems: "center", gap: 12, flex: 1, minWidth: 280 }}>
              <div style={{ position: "relative", width: "100%", maxWidth: 440 }}>
                <Search
                  size={16}
                  style={{ position: "absolute", left: 12, top: "50%", transform: "translateY(-50%)", color: "var(--muted)" }}
                />
                <input
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="Поиск по названию или девизу знамени…"
                  style={{
                    width: "100%",
                    padding: "9px 12px 9px 38px",
                    background: "var(--surface)",
                    border: "1px solid var(--border)",
                    borderRadius: "var(--radius-sm)",
                    color: "var(--fg)",
                    fontSize: "var(--text-xs)",
                  }}
                />
              </div>
            </div>

            <div style={{ display: "flex", gap: 8 }}>
              {(
                [
                  { id: "all", label: "Все" },
                  { id: "open", label: "Открытые" },
                  { id: "request", label: "По заявке" },
                ] as const
              ).map((tab) => {
                const active = policyFilter === tab.id
                return (
                  <button
                    key={tab.id}
                    onClick={() => setPolicyFilter(tab.id)}
                    style={{
                      padding: "7px 16px",
                      fontSize: "var(--text-xs)",
                      fontWeight: active ? 600 : 400,
                      color: active ? "var(--accent)" : "var(--muted)",
                      background: active ? "color-mix(in oklab, var(--accent), transparent 85%)" : "var(--surface)",
                      border: `1px solid ${active ? "var(--accent)" : "var(--border)"}`,
                      borderRadius: "var(--radius-sm)",
                      cursor: "pointer",
                      transition: "all 0.15s ease",
                    }}
                  >
                    {tab.label}
                  </button>
                )
              })}
            </div>
          </div>

          {/* Список гильдий — полноэкранная сетка */}
          {filteredGuilds.length === 0 ? (
            <div
              className="fantasy-window"
              style={{ padding: 48, textAlign: "center", color: "var(--muted)", fontSize: "var(--text-sm)" }}
            >
              {guilds.length === 0
                ? `В Тамриэле пока не поднято ни одного знамени. Стань первым лидером и учреди гильдию за ${CREATE_COST} золота!`
                : "По вашему запросу не найдено подходящих гильдий."}
            </div>
          ) : (
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(340px, 1fr))", gap: 20 }}>
              {filteredGuilds.map((g) => {
                const isJoining = joiningId === g.id
                return (
                  <div key={g.id} className="guild-shield-card">
                    <div style={{ display: "flex", alignItems: "flex-start", gap: 16 }}>
                      <div className="guild-emblem-crest" style={{ width: 62, height: 62, minWidth: 62, fontSize: 32 }}>
                        {g.emblem}
                      </div>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div
                          style={{
                            fontFamily: "var(--font-display)",
                            fontSize: 19,
                            fontWeight: 700,
                            color: "var(--fg)",
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                            whiteSpace: "nowrap",
                          }}
                        >
                          {g.name}
                        </div>
                        <div
                          style={{
                            display: "flex",
                            alignItems: "center",
                            gap: 8,
                            fontSize: 12,
                            color: "var(--muted)",
                            marginTop: 4,
                          }}
                        >
                          <span style={{ color: "var(--gold)", fontFamily: "var(--font-mono)", fontWeight: 600 }}>
                            Ранг {g.level}
                          </span>
                          <span>·</span>
                          <span>{g.member_count} чел.</span>
                          <span>·</span>
                          <span
                            style={{
                              padding: "2px 7px",
                              borderRadius: 3,
                              fontSize: 10,
                              background: g.policy === "open" ? "rgba(34, 197, 94, 0.15)" : "rgba(234, 179, 8, 0.15)",
                              color: g.policy === "open" ? "var(--success)" : "var(--gold)",
                              border: `1px solid ${g.policy === "open" ? "rgba(34, 197, 94, 0.3)" : "rgba(234, 179, 8, 0.3)"}`,
                            }}
                          >
                            {GUILD_POLICY_RU[g.policy] || g.policy}
                          </span>
                        </div>
                      </div>
                    </div>

                    {g.motto && (
                      <div
                        style={{
                          fontFamily: "var(--font-display)",
                          fontStyle: "italic",
                          fontSize: 14,
                          color: "var(--accent)",
                          lineHeight: 1.45,
                          paddingLeft: 6,
                          borderLeft: "2px solid color-mix(in oklab, var(--accent), transparent 60%)",
                        }}
                      >
                        «{g.motto}»
                      </div>
                    )}

                    <div style={{ marginTop: "auto", paddingTop: 10 }}>
                      {g.policy === "open" ? (
                        <button
                          onClick={() => handleJoin(g.id)}
                          disabled={isJoining}
                          style={{
                            width: "100%",
                            padding: "10px 0",
                            background: "var(--accent)",
                            color: "var(--accent-on)",
                            border: "none",
                            borderRadius: "var(--radius-sm)",
                            fontSize: "var(--text-xs)",
                            fontWeight: 700,
                            cursor: isJoining ? "default" : "pointer",
                            transition: "all 0.2s ease",
                          }}
                        >
                          {isJoining ? "Вступаем…" : "Вступить в ряды"}
                        </button>
                      ) : (
                        <button
                          onClick={() => handleJoin(g.id)}
                          disabled={isJoining}
                          style={{
                            width: "100%",
                            padding: "10px 0",
                            background: "transparent",
                            color: "var(--muted)",
                            border: "1px solid var(--border)",
                            borderRadius: "var(--radius-sm)",
                            fontSize: "var(--text-xs)",
                            cursor: isJoining ? "default" : "pointer",
                            transition: "all 0.2s ease",
                          }}
                        >
                          {isJoining ? "Подаём…" : "Подать прошение"}
                        </button>
                      )}
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </>
      )}
    </div>
  )
}

// ── Chamber 1: Алтарь и Казна (2 просторные колонки) ─────────────────────────
const OFFER_PRESETS = [50, 100, 250, 500]
const TREASURY_PRESETS = [50, 200, 500]

function AltarAndTreasuryChamber({
  detail,
  heroGold,
  onChanged,
}: {
  detail: GuildDetail
  heroGold: number
  onChanged: () => void
}) {
  const guild = detail.guild
  const altar = detail.my_altar
  const treasury = detail.treasury

  const [offerAmount, setOfferAmount] = useState(100)
  const [treasuryAmount, setTreasuryAmount] = useState(100)
  const [offerBusy, setOfferBusy] = useState(false)
  const [treasuryBusy, setTreasuryBusy] = useState(false)
  const [feastBusy, setFeastBusy] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)

  const handleOffer = async (amt: number) => {
    if (offerBusy || amt <= 0) return
    setOfferBusy(true)
    setNotice(null)
    try {
      const res = await api.offerGold(guild.id, amt)
      setNotice(
        res.level_ups > 0
          ? `🔥 Алтарь принял ${fmt(amt)} 🪙! Знамя гильдии достигло ${res.guild.level} уровня!`
          : `🔥 Алтарь принял ${fmt(amt)} 🪙 — начислено +${res.points_awarded} очков гильдии.`
      )
      onChanged()
    } catch (e: any) {
      const msg = e?.message || String(e)
      setNotice(msg.includes("not_enough_gold") ? "Не хватает золота в кошельке." : "Подношение не принято алтарём.")
    } finally {
      setOfferBusy(false)
    }
  }

  const handleDeposit = async (amt: number) => {
    if (treasuryBusy || amt <= 0) return
    setTreasuryBusy(true)
    setNotice(null)
    try {
      const res = await api.depositTreasury(guild.id, amt)
      setNotice(`💰 Казна пополнена на ${fmt(amt)} 🪙 (баланс: ${fmt(res.treasury)} 🪙).`)
      onChanged()
    } catch (e: any) {
      const msg = e?.message || String(e)
      setNotice(msg.includes("not_enough_gold") ? "Не хватает золота." : "Вклад в казну отклонён.")
    } finally {
      setTreasuryBusy(false)
    }
  }

  const handleFeast = async () => {
    if (feastBusy) return
    setFeastBusy(true)
    setNotice(null)
    try {
      await api.holdFeast(guild.id)
      setNotice("🍻 Пир начался! Весь Тамриэль славит соратников: +5% опыта на 4 часа!")
      onChanged()
    } catch (e: any) {
      const msg = e?.message || String(e)
      setNotice(
        msg.includes("not_enough_treasury")
          ? `В казне недостаточно золота (нужно ${treasury?.feast_cost ?? 300} 🪙).`
          : msg.includes("forbidden")
            ? "Пир могут закатывать только лидер и офицеры."
            : "Не удалось устроить пир."
      )
    } finally {
      setFeastBusy(false)
    }
  }

  const nextExp = guild.exp_to_next ?? 0
  const expPct = nextExp > 0 ? Math.min(100, Math.round((guild.exp / nextExp) * 100)) : 100

  return (
    <div className="anim-fade-up" style={{ display: "flex", flexDirection: "column", gap: 24, width: "100%" }}>
      {notice && (
        <div
          role="status"
          style={{
            padding: "12px 18px",
            background: "color-mix(in oklab, var(--accent), transparent 88%)",
            border: "1px solid color-mix(in oklab, var(--accent), transparent 60%)",
            borderRadius: "var(--radius-sm)",
            fontSize: "var(--text-xs)",
            color: "var(--gold)",
          }}
        >
          {notice}
        </div>
      )}

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(440px, 1fr))", gap: 24 }}>
        {/* Карточка Священного Алтаря */}
        <div className="fantasy-window" style={{ padding: 28 }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <span style={{ fontSize: 28 }}>🔥</span>
              <div>
                <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: 0, color: "var(--fg)" }}>
                  Священный Алтарь Девяти
                </h3>
                <div style={{ fontSize: 12, color: "var(--muted)" }}>Жертвенник опыта и благословений</div>
              </div>
            </div>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: 13, color: "var(--gold)", fontWeight: 700 }}>
              Ранг {guild.level}
            </span>
          </div>

          {/* Шкала опыта алтаря */}
          <div style={{ marginBottom: 20 }}>
            <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12, color: "var(--muted)", marginBottom: 6, fontFamily: "var(--font-mono)" }}>
              <span>Прогресс благодати</span>
              <span>{guild.level >= (guild.max_level ?? 20) ? "Максимум" : `${fmt(guild.exp)} / ${fmt(guild.exp_to_next)} XP`}</span>
            </div>
            <div className="guild-exp-track">
              <div className="guild-exp-fill" style={{ width: `${expPct}%` }} />
            </div>
          </div>

          {/* Форма подношения */}
          <div style={{ marginBottom: 20 }}>
            <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)", marginBottom: 10 }}>
              Возложить септимы на алтарь:
            </div>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 12 }}>
              {OFFER_PRESETS.map((p) => (
                <button
                  key={p}
                  type="button"
                  onClick={() => handleOffer(p)}
                  disabled={offerBusy || heroGold < p}
                  style={{
                    padding: "6px 14px",
                    background: "var(--surface-raised)",
                    border: "1px solid var(--border)",
                    borderRadius: "var(--radius-sm)",
                    color: heroGold < p ? "var(--muted)" : "var(--gold)",
                    fontFamily: "var(--font-mono)",
                    fontSize: 13,
                    fontWeight: 600,
                    cursor: offerBusy || heroGold < p ? "default" : "pointer",
                    opacity: heroGold < p ? 0.5 : 1,
                  }}
                >
                  +{p} 🪙
                </button>
              ))}
            </div>

            <div style={{ display: "flex", gap: 10 }}>
              <input
                type="number"
                min={1}
                value={offerAmount}
                onChange={(e) => setOfferAmount(Math.max(1, Math.floor(Number(e.target.value) || 0)))}
                aria-label="Своя сумма подношения"
                style={{
                  width: 120,
                  padding: "8px 12px",
                  background: "var(--bg-elevated)",
                  border: "1px solid var(--border)",
                  borderRadius: "var(--radius-sm)",
                  color: "var(--fg)",
                  fontFamily: "var(--font-mono)",
                  fontSize: 13,
                }}
              />
              <button
                type="button"
                onClick={() => handleOffer(offerAmount)}
                disabled={offerBusy || offerAmount <= 0 || heroGold < offerAmount}
                style={{
                  flex: 1,
                  padding: "8px 20px",
                  background: "var(--accent)",
                  color: "var(--accent-on)",
                  border: "none",
                  borderRadius: "var(--radius-sm)",
                  fontWeight: 700,
                  fontSize: "var(--text-xs)",
                  cursor: offerBusy || offerAmount <= 0 || heroGold < offerAmount ? "default" : "pointer",
                  opacity: offerBusy || offerAmount <= 0 || heroGold < offerAmount ? 0.5 : 1,
                }}
              >
                {offerBusy ? "Возлагаем…" : "Возложить подношение"}
              </button>
            </div>
          </div>

          {/* Статистика личного вклада */}
          {altar && (
            <div
              style={{
                padding: "12px 16px",
                background: "var(--surface-raised)",
                borderRadius: "var(--radius-sm)",
                border: "1px solid var(--border)",
                fontSize: 12,
                color: "var(--muted)",
                fontFamily: "var(--font-mono)",
                display: "flex",
                flexDirection: "column",
                gap: 6,
              }}
            >
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <span>Мой личный вклад:</span>
                <span style={{ color: "var(--fg)", fontWeight: 600 }}>{fmt(altar.contributed)} 🪙</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <span>Очки верности гильдии:</span>
                <span style={{ color: "var(--gold)", fontWeight: 700 }}>{fmt(altar.points)} очков</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <span>Дневной лимит очков:</span>
                <span>+{fmt(altar.points_today)} / {fmt(altar.daily_cap)}</span>
              </div>
            </div>
          )}

          {/* Хроника подношений */}
          {(detail.offerings ?? []).length > 0 && (
            <div style={{ marginTop: 18, borderTop: "1px solid var(--border)", paddingTop: 14 }}>
              <div style={{ fontSize: 12, color: "var(--muted)", marginBottom: 8, fontWeight: 700 }}>
                📜 Недавние жертвы соратников:
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                {(detail.offerings ?? []).slice(0, 5).map((o, i) => (
                  <div key={i} style={{ display: "flex", justifyContent: "space-between", fontSize: 12 }}>
                    <span style={{ color: "var(--fg)" }}>{o.username}</span>
                    <span style={{ color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
                      +{fmt(o.amount)} 🪙 ({o.points} очк.)
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Карточка Казны и Пира */}
        {treasury && (
          <div className="fantasy-window" style={{ padding: 28 }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <span style={{ fontSize: 28 }}>💰</span>
                <div>
                  <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: 0, color: "var(--fg)" }}>
                    Казна гильдии
                  </h3>
                  <div style={{ fontSize: 12, color: "var(--muted)" }}>Общий фонд и великие пиры</div>
                </div>
              </div>
              <div style={{ fontFamily: "var(--font-mono)", fontSize: 18, color: "var(--gold)", fontWeight: 800 }}>
                {fmt(treasury.amount)} 🪙
              </div>
            </div>

            {/* Блок Пиршества */}
            <div
              style={{
                padding: "16px 20px",
                background: treasury.feast_active
                  ? "color-mix(in oklab, var(--accent), transparent 90%)"
                  : "var(--surface-raised)",
                border: `1px solid ${treasury.feast_active ? "var(--accent)" : "var(--border)"}`,
                borderRadius: "var(--radius-md)",
                marginBottom: 20,
              }}
            >
              {treasury.feast_active ? (
                <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                  <Beer size={26} style={{ color: "var(--gold)" }} />
                  <div>
                    <div style={{ color: "var(--gold)", fontWeight: 700, fontSize: "var(--text-sm)" }}>
                      Пир соратников в разгаре!
                    </div>
                    <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 3 }}>
                      Вся гильдия получает <strong style={{ color: "var(--gold)" }}>+5% опыта</strong>. До конца:{" "}
                      {treasury.boost_until
                        ? `${Math.max(0, Math.round((new Date(`${treasury.boost_until}Z`).getTime() - Date.now()) / 60000))} мин.`
                        : "несколько минут"}
                    </div>
                  </div>
                </div>
              ) : (
                <div>
                  <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                      <Beer size={20} style={{ color: "var(--accent)" }} />
                      <span style={{ fontWeight: 700, fontSize: "var(--text-sm)", color: "var(--fg)" }}>
                        Устроить великий пир
                      </span>
                    </div>
                    <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--gold)", fontWeight: 600 }}>
                      Цена: {treasury.feast_cost} 🪙
                    </span>
                  </div>
                  <p style={{ fontSize: 12, color: "var(--muted)", margin: "0 0 12px", lineHeight: 1.5 }}>
                    Пир дарует всем соратникам +5% опыта на 4 часа. Проводить могут лидер и офицеры.
                  </p>
                  <button
                    type="button"
                    onClick={handleFeast}
                    disabled={feastBusy || !treasury.my_can_feast || treasury.amount < treasury.feast_cost}
                    style={{
                      width: "100%",
                      padding: "10px 0",
                      background:
                        treasury.my_can_feast && treasury.amount >= treasury.feast_cost
                          ? "var(--accent)"
                          : "var(--surface)",
                      border: `1px solid ${
                        treasury.my_can_feast && treasury.amount >= treasury.feast_cost
                          ? "transparent"
                          : "var(--border)"
                      }`,
                      borderRadius: "var(--radius-sm)",
                      color:
                        treasury.my_can_feast && treasury.amount >= treasury.feast_cost
                          ? "var(--accent-on)"
                          : "var(--muted)",
                      fontWeight: 700,
                      fontSize: "var(--text-xs)",
                      cursor:
                        feastBusy || !treasury.my_can_feast || treasury.amount < treasury.feast_cost
                          ? "default"
                          : "pointer",
                      opacity: treasury.my_can_feast && treasury.amount >= treasury.feast_cost ? 1 : 0.5,
                      transition: "all 0.2s ease",
                    }}
                  >
                    {feastBusy ? "Организуем пир…" : `🍻 Закатить пир (${treasury.feast_cost} 🪙 из казны)`}
                  </button>
                </div>
              )}
            </div>

            {/* Вклад в казну */}
            <div style={{ marginBottom: 20 }}>
              <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)", marginBottom: 10 }}>
                Пополнить казну гильдии:
              </div>
              <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 12 }}>
                {TREASURY_PRESETS.map((p) => (
                  <button
                    key={p}
                    type="button"
                    onClick={() => handleDeposit(p)}
                    disabled={treasuryBusy || heroGold < p}
                    style={{
                      padding: "6px 14px",
                      background: "var(--surface-raised)",
                      border: "1px solid var(--border)",
                      borderRadius: "var(--radius-sm)",
                      color: heroGold < p ? "var(--muted)" : "var(--gold)",
                      fontFamily: "var(--font-mono)",
                      fontSize: 13,
                      fontWeight: 600,
                      cursor: treasuryBusy || heroGold < p ? "default" : "pointer",
                      opacity: heroGold < p ? 0.5 : 1,
                    }}
                  >
                    +{p} 🪙
                  </button>
                ))}
              </div>

              <div style={{ display: "flex", gap: 10 }}>
                <input
                  type="number"
                  min={1}
                  value={treasuryAmount}
                  onChange={(e) => setTreasuryAmount(Math.max(1, Math.floor(Number(e.target.value) || 0)))}
                  aria-label="Своя сумма вклада в казну"
                  style={{
                    width: 120,
                    padding: "8px 12px",
                    background: "var(--bg-elevated)",
                    border: "1px solid var(--border)",
                    borderRadius: "var(--radius-sm)",
                    color: "var(--fg)",
                    fontFamily: "var(--font-mono)",
                    fontSize: 13,
                  }}
                />
                <button
                  type="button"
                  onClick={() => handleDeposit(treasuryAmount)}
                  disabled={treasuryBusy || treasuryAmount <= 0 || heroGold < treasuryAmount}
                  style={{
                    flex: 1,
                    padding: "8px 20px",
                    background: "var(--surface-raised)",
                    border: "1px solid var(--border)",
                    borderRadius: "var(--radius-sm)",
                    color: "var(--fg)",
                    fontSize: "var(--text-xs)",
                    fontWeight: 600,
                    cursor: treasuryBusy || treasuryAmount <= 0 || heroGold < treasuryAmount ? "default" : "pointer",
                    opacity: treasuryBusy || treasuryAmount <= 0 || heroGold < treasuryAmount ? 0.5 : 1,
                  }}
                >
                  {treasuryBusy ? "Вносим…" : "Внести в казну"}
                </button>
              </div>
            </div>

            {/* Книга казны */}
            {(treasury.log ?? []).length > 0 && (
              <div style={{ borderTop: "1px solid var(--border)", paddingTop: 14 }}>
                <div style={{ fontSize: 12, color: "var(--muted)", marginBottom: 8, fontWeight: 700 }}>
                  📖 Записи гроссбуха:
                </div>
                <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                  {(treasury.log ?? []).slice(0, 5).map((l, i) => (
                    <div key={i} style={{ display: "flex", justifyContent: "space-between", fontSize: 12 }}>
                      <span style={{ color: l.kind === "deposit" ? "var(--fg)" : "var(--gold)" }}>
                        {l.kind === "deposit" ? "Пополнение" : "Пир соратников"}
                      </span>
                      <span style={{ color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
                        {l.kind === "deposit" ? "+" : "−"}{fmt(l.amount)} 🪙 (итог: {fmt(l.balance_after)})
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

// ── Chamber 2: Лавка Соратников (полноэкранная витрина) ───────────────────────
function ShopChamber() {
  const [catalog, setCatalog] = useState<any[]>([])
  const [myPoints, setMyPoints] = useState<number | null>(null)
  const [buyingName, setBuyingName] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      const res = await api.getGuildShop()
      setCatalog(res.catalog ?? [])
      setMyPoints(res.my_points)
    } catch {}
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const buy = async (name: string) => {
    if (buyingName) return
    setBuyingName(name)
    setNotice(null)
    try {
      const res = await api.buyGuildItem(name)
      setNotice(`📦 Приобретено: «${res.item.name}»! Остаток очков: ${res.points_left}.`)
      await load()
    } catch (e: any) {
      const msg = e?.message || String(e)
      setNotice(msg.includes("not_enough_points") ? "Недостаточно очков верности гильдии." : "Не удалось совершить покупку.")
    } finally {
      setBuyingName(null)
    }
  }

  const statBadges = (item: any) => {
    const list: string[] = []
    if (item.defense_bonus) list.push(`+${item.defense_bonus} Защита`)
    if (item.attack_bonus) list.push(`+${item.attack_bonus} Атака`)
    if (item.hp_bonus) list.push(`+${item.hp_bonus} HP`)
    if (item.heal_hp) list.push(`Восст. ${item.heal_hp} HP`)
    if (item.heal_sp) list.push(`Восст. ${item.heal_sp} SP`)
    if (item.buff_attack) list.push(`+${item.buff_attack} Атака (баф)`)
    return list
  }

  return (
    <div className="anim-fade-up" style={{ width: "100%" }}>
      {/* Шапка лавки с балансом */}
      <div
        className="fantasy-window"
        style={{
          padding: "20px 24px",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          marginBottom: 24,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <ShoppingBag size={24} style={{ color: "var(--accent)" }} />
          <div>
            <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: 0, color: "var(--fg)" }}>
              Лавка интенданта
            </h3>
            <div style={{ fontSize: 12, color: "var(--muted)" }}>
              Особое снаряжение и снадобья, доступные за подношения алтарю
            </div>
          </div>
        </div>

        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            padding: "8px 18px",
            background: "color-mix(in oklab, var(--accent), transparent 85%)",
            border: "1px solid color-mix(in oklab, var(--accent), transparent 50%)",
            borderRadius: "var(--radius-pill)",
          }}
        >
          <Sparkles size={18} style={{ color: "var(--gold)" }} />
          <span style={{ fontSize: 14, color: "var(--gold)", fontFamily: "var(--font-mono)", fontWeight: 700 }}>
            {myPoints === null ? "—" : `${fmt(myPoints)} очков`}
          </span>
        </div>
      </div>

      {notice && (
        <div
          role="status"
          style={{
            padding: "12px 18px",
            background: "color-mix(in oklab, var(--accent), transparent 88%)",
            border: "1px solid color-mix(in oklab, var(--accent), transparent 60%)",
            borderRadius: "var(--radius-sm)",
            fontSize: "var(--text-xs)",
            color: "var(--gold)",
            marginBottom: 24,
          }}
        >
          {notice}
        </div>
      )}

      {/* Сетка предметов */}
      {catalog.length === 0 ? (
        <div className="fantasy-window" style={{ padding: 48, textAlign: "center", color: "var(--muted)" }}>
          Лавка интенданта пока пуста.
        </div>
      ) : (
        <div className="guild-shop-grid">
          {catalog.map((entry) => {
            const item = entry.item
            const affordable = myPoints !== null && myPoints >= entry.points
            const stats = item ? statBadges(item) : []
            const isBuying = buyingName === entry.name

            return (
              <div key={entry.name} className="guild-shop-card">
                <div style={{ display: "flex", alignItems: "flex-start", gap: 14 }}>
                  <div className="guild-shop-icon-socket">
                    {item?.icon || "📦"}
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div
                      style={{
                        fontFamily: "var(--font-display)",
                        fontSize: 17,
                        fontWeight: 700,
                        color: "var(--fg)",
                      }}
                    >
                      {entry.name}
                    </div>
                    <div style={{ fontSize: 11, color: "var(--muted)", textTransform: "capitalize", marginTop: 2 }}>
                      {item?.type || "Предмет"} · {item?.slot || "Снаряжение"}
                    </div>
                  </div>
                </div>

                {stats.length > 0 && (
                  <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
                    {stats.map((st, i) => (
                      <span key={i} className="guild-buff-chip">
                        {st}
                      </span>
                    ))}
                  </div>
                )}

                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    marginTop: "auto",
                    paddingTop: 10,
                    borderTop: "1px solid var(--border)",
                  }}
                >
                  <span
                    style={{
                      fontFamily: "var(--font-mono)",
                      fontSize: 14,
                      fontWeight: 700,
                      color: affordable ? "var(--gold)" : "var(--muted)",
                    }}
                  >
                    {fmt(entry.points)} очков
                  </span>

                  <button
                    type="button"
                    onClick={() => buy(entry.name)}
                    disabled={isBuying || !affordable || !item}
                    style={{
                      padding: "7px 16px",
                      background: affordable ? "var(--accent)" : "var(--surface-raised)",
                      border: "none",
                      borderRadius: "var(--radius-sm)",
                      color: affordable ? "var(--accent-on)" : "var(--muted)",
                      fontWeight: 700,
                      fontSize: "var(--text-xs)",
                      cursor: affordable && !isBuying ? "pointer" : "default",
                      opacity: affordable ? 1 : 0.5,
                      transition: "all 0.15s ease",
                    }}
                  >
                    {isBuying ? "Покупка…" : "Приобрести"}
                  </button>
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── Chamber 3: Зал Соратников и Заявки ───────────────────────────────────────
function RosterAndAppsChamber({
  guildId,
  members,
  myRole,
  isLeader,
  onChanged,
}: {
  guildId: string
  members: GuildMemberRow[]
  myRole: string
  isLeader: boolean
  onChanged: () => void
}) {
  const isOfficer = myRole === "leader" || myRole === "officer"
  const [apps, setApps] = useState<any[]>([])
  const [appsBusy, setAppsBusy] = useState<string | null>(null)
  const [rosterBusy, setRosterBusy] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [filterSearch, setFilterSearch] = useState("")

  const loadApps = useCallback(async () => {
    if (!isOfficer) return
    try {
      const res = await api.getGuildApplications(guildId)
      setApps(res.applications ?? [])
    } catch {
      setApps([])
    }
  }, [guildId, isOfficer])

  useEffect(() => {
    loadApps()
  }, [loadApps])

  const decideApp = async (appId: string, decision: "approved" | "rejected") => {
    if (appsBusy) return
    setAppsBusy(appId)
    try {
      await api.decideGuildApplication(guildId, appId, decision)
      await loadApps()
      onChanged()
    } catch {
      await loadApps()
    } finally {
      setAppsBusy(null)
    }
  }

  const toggleRole = async (userId: string, targetRole: "officer" | "member") => {
    if (rosterBusy) return
    setRosterBusy(userId)
    setNotice(null)
    try {
      await api.setGuildRole(guildId, userId, targetRole)
      onChanged()
    } catch (e: any) {
      const msg = e?.message || String(e)
      setNotice(msg.includes("officers_cap") ? "Офицеров не может быть больше трёх." : "Не удалось изменить роль.")
    } finally {
      setRosterBusy(null)
    }
  }

  const kick = async (userId: string, username: string) => {
    if (rosterBusy) return
    setRosterBusy(userId)
    setNotice(null)
    try {
      await api.kickGuildMember(guildId, userId)
      setNotice(`Соратник ${username} исключён из гильдии.`)
      onChanged()
    } catch {
      setNotice("Не удалось исключить — офицеров сначала нужно разжаловать.")
    } finally {
      setRosterBusy(null)
    }
  }

  const filteredMembers = useMemo(() => {
    if (!filterSearch) return members
    return members.filter((m) => m.username.toLowerCase().includes(filterSearch.toLowerCase()))
  }, [members, filterSearch])

  return (
    <div className="anim-fade-up" style={{ display: "flex", flexDirection: "column", gap: 24, width: "100%" }}>
      {notice && (
        <div
          role="status"
          style={{
            padding: "12px 18px",
            background: "color-mix(in oklab, var(--accent), transparent 88%)",
            border: "1px solid color-mix(in oklab, var(--accent), transparent 60%)",
            borderRadius: "var(--radius-sm)",
            fontSize: "var(--text-xs)",
            color: "var(--gold)",
          }}
        >
          {notice}
        </div>
      )}

      {/* Заявки на вступление (только для офицеров/лидеров) */}
      {isOfficer && apps.length > 0 && (
        <div className="fantasy-window" style={{ padding: 24, borderColor: "var(--accent)" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 16 }}>
            <UserCheck size={22} style={{ color: "var(--gold)" }} />
            <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: 0, color: "var(--fg)" }}>
              Прошения о вступлении ({apps.length})
            </h3>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {apps.map((a) => (
              <div
                key={a.id}
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  padding: "12px 16px",
                  background: "var(--surface-raised)",
                  border: "1px solid var(--border)",
                  borderRadius: "var(--radius-sm)",
                }}
              >
                <div>
                  <div style={{ fontWeight: 600, fontSize: "var(--text-sm)", color: "var(--fg)" }}>
                    {a.username}
                  </div>
                  <div style={{ fontSize: 11, color: "var(--muted)" }}>
                    Подано: {fmtDate(a.inserted_at)}
                  </div>
                </div>

                <div style={{ display: "flex", gap: 10 }}>
                  <button
                    type="button"
                    onClick={() => decideApp(a.id, "approved")}
                    disabled={appsBusy !== null}
                    style={{
                      display: "inline-flex",
                      alignItems: "center",
                      gap: 4,
                      padding: "7px 16px",
                      background: "rgba(34, 197, 94, 0.15)",
                      border: "1px solid rgba(34, 197, 94, 0.4)",
                      borderRadius: "var(--radius-sm)",
                      color: "var(--success)",
                      fontSize: 12,
                      fontWeight: 600,
                      cursor: appsBusy !== null ? "default" : "pointer",
                    }}
                  >
                    <Check size={14} /> Принять
                  </button>
                  <button
                    type="button"
                    onClick={() => decideApp(a.id, "rejected")}
                    disabled={appsBusy !== null}
                    style={{
                      display: "inline-flex",
                      alignItems: "center",
                      gap: 4,
                      padding: "7px 14px",
                      background: "rgba(239, 68, 68, 0.12)",
                      border: "1px solid rgba(239, 68, 68, 0.35)",
                      borderRadius: "var(--radius-sm)",
                      color: "var(--danger)",
                      fontSize: 12,
                      cursor: appsBusy !== null ? "default" : "pointer",
                    }}
                  >
                    <X size={14} /> Отклонить
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Табель о рангах (Состав гильдии) */}
      <div className="fantasy-window" style={{ padding: 28 }}>
        <div
          style={{
            display: "flex",
            flexWrap: "wrap",
            alignItems: "center",
            justifyContent: "space-between",
            gap: 16,
            marginBottom: 20,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <Users size={24} style={{ color: "var(--accent)" }} />
            <div>
              <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: 0, color: "var(--fg)" }}>
                Табель о рангах ({members.length})
              </h3>
              <div style={{ fontSize: 12, color: "var(--muted)" }}>
                Соратники знамени, их подвиги и заслуги перед алтарём
              </div>
            </div>
          </div>

          <div style={{ position: "relative", width: 260 }}>
            <Search
              size={14}
              style={{ position: "absolute", left: 12, top: "50%", transform: "translateY(-50%)", color: "var(--muted)" }}
            />
            <input
              value={filterSearch}
              onChange={(e) => setFilterSearch(e.target.value)}
              placeholder="Поиск соратника…"
              style={{
                width: "100%",
                padding: "8px 12px 8px 34px",
                background: "var(--surface-raised)",
                border: "1px solid var(--border)",
                borderRadius: "var(--radius-sm)",
                fontSize: 12,
                color: "var(--fg)",
              }}
            />
          </div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {filteredMembers.map((m) => {
            const isUserLeader = m.role === "leader"
            const isUserOfficer = m.role === "officer"
            return (
              <div key={m.user_id} className="guild-roster-row">
                <div style={{ width: 120, flexShrink: 0 }}>
                  <span
                    className={`guild-role-badge ${
                      isUserLeader ? "role-leader" : isUserOfficer ? "role-officer" : "role-member"
                    }`}
                  >
                    {isUserLeader && <Crown size={12} />}
                    {isUserOfficer && <Shield size={12} />}
                    {GUILD_ROLE_RU[m.role] || m.role}
                  </span>
                </div>

                <div style={{ flex: 1, minWidth: 140 }}>
                  <div style={{ fontWeight: 600, fontSize: "var(--text-sm)", color: "var(--fg)" }}>
                    {m.username}
                  </div>
                  <div style={{ fontSize: 11, color: "var(--muted)" }}>
                    В братстве с {fmtDate(m.joined_at)}
                  </div>
                </div>

                <div style={{ textAlign: "right", fontFamily: "var(--font-mono)", fontSize: 13, marginRight: 12 }}>
                  <div style={{ color: "var(--gold)", fontWeight: 600 }}>{fmt(m.contributed)} 🪙</div>
                  <div style={{ fontSize: 11, color: "var(--muted)" }}>{fmt(m.points)} очков</div>
                </div>

                {isLeader && !isUserLeader && (
                  <div style={{ display: "flex", gap: 8, flexShrink: 0 }}>
                    <button
                      type="button"
                      onClick={() => toggleRole(m.user_id, isUserOfficer ? "member" : "officer")}
                      disabled={rosterBusy !== null}
                      style={{
                        padding: "5px 12px",
                        fontSize: 11,
                        background: "var(--surface-raised)",
                        border: "1px solid var(--border)",
                        borderRadius: "var(--radius-sm)",
                        color: isUserOfficer ? "var(--muted)" : "var(--accent)",
                        cursor: rosterBusy !== null ? "default" : "pointer",
                      }}
                    >
                      {isUserOfficer ? "Разжаловать" : "↑ В офицеры"}
                    </button>
                    {!isUserOfficer && (
                      <button
                        type="button"
                        onClick={() => kick(m.user_id, m.username)}
                        disabled={rosterBusy !== null}
                        style={{
                          padding: "5px 12px",
                          fontSize: 11,
                          background: "rgba(239, 68, 68, 0.1)",
                          border: "1px solid rgba(239, 68, 68, 0.3)",
                          borderRadius: "var(--radius-sm)",
                          color: "var(--danger)",
                          cursor: rosterBusy !== null ? "default" : "pointer",
                        }}
                      >
                        Изгнать
                      </button>
                    )}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}

// ── Chamber 4: Ратуша и Вести Тамриэля (просторный сплит на 1080p) ────────────
function CouncilAndNewsChamber({
  guildId,
  myUserId,
}: {
  guildId: string
  myUserId: string | null
}) {
  const [messages, setMessages] = useState<GuildChatMessage[]>([])
  const [news, setNews] = useState<any[]>([])
  const [text, setText] = useState("")
  const [sending, setSending] = useState(false)
  const [cooldown, setCooldown] = useState(0)
  const [notice, setNotice] = useState<string | null>(null)
  const listRef = useRef<HTMLDivElement | null>(null)

  const loadMessages = useCallback(async () => {
    try {
      const res = await api.getGuildMessages(guildId)
      setMessages(res.messages ?? [])
    } catch {}
  }, [guildId])

  const loadNews = useCallback(async () => {
    try {
      const res = await api.getGuildNews()
      setNews(res.news ?? [])
    } catch {}
  }, [])

  useEffect(() => {
    loadMessages()
    loadNews()
    const iv = setInterval(loadMessages, 4000)
    return () => clearInterval(iv)
  }, [loadMessages, loadNews])

  // Автоскролл
  useEffect(() => {
    const el = listRef.current
    if (el) el.scrollTop = el.scrollHeight
  }, [messages])

  // Кулдаун отправки
  useEffect(() => {
    if (cooldown <= 0) return
    const t = setTimeout(() => setCooldown((c) => c - 1), 1000)
    return () => clearTimeout(t)
  }, [cooldown])

  const handleSend = async () => {
    const body = text.trim()
    if (!body || sending || cooldown > 0) return
    setSending(true)
    setNotice(null)
    try {
      await api.sendGuildMessage(guildId, body)
      setText("")
      setCooldown(2)
      await loadMessages()
    } catch (e: any) {
      const msg = e?.message || String(e)
      setNotice(msg.includes("rate_limited") ? "Слишком частая отправка — подожди секунду." : "Сообщение не отправлено.")
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="anim-fade-up" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(460px, 1fr))", gap: 24, width: "100%" }}>
      {/* Левая колонка: Чат братства */}
      <div className="fantasy-window" style={{ padding: 26, display: "flex", flexDirection: "column" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 16 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <MessageSquare size={22} style={{ color: "var(--accent)" }} />
            <div>
              <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: 0, color: "var(--fg)" }}>
                Ратуша соратников
              </h3>
              <div style={{ fontSize: 12, color: "var(--muted)" }}>Живой разговор у очага</div>
            </div>
          </div>
          <span style={{ fontSize: 12, color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
            {messages.length} сообщений
          </span>
        </div>

        <div ref={listRef} className="guild-chat-container">
          {messages.length === 0 && (
            <div style={{ textAlign: "center", color: "var(--muted)", fontSize: "var(--text-xs)", padding: "36px 0" }}>
              В ратуше тихо потрескивают дрова. Напиши первое слово своим соратникам!
            </div>
          )}

          {messages.map((m) => {
            if (m.kind === "system") {
              return (
                <div key={m.id} className="guild-chat-msg system">
                  ⚔️ {m.body}
                </div>
              )
            }
            const isMine = m.user_id === myUserId
            return (
              <div key={m.id} className={`guild-chat-msg ${isMine ? "mine" : "theirs"}`}>
                <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 14, marginBottom: 3 }}>
                  <span
                    style={{
                      fontSize: 11,
                      fontWeight: 700,
                      color: isMine ? "var(--gold)" : "var(--accent)",
                    }}
                  >
                    {isMine ? "Ты" : m.username}
                  </span>
                  <span style={{ fontSize: 10, color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
                    {fmtTime(m.inserted_at)}
                  </span>
                </div>
                <div style={{ color: "var(--fg)", wordBreak: "break-word" }}>{m.body}</div>
              </div>
            )
          })}
        </div>

        {notice && (
          <div style={{ fontSize: 12, color: "var(--gold)", marginTop: 8 }}>
            {notice}
          </div>
        )}

        {/* Поле ввода */}
        <div style={{ display: "flex", gap: 10, marginTop: 14 }}>
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                handleSend()
              }
            }}
            maxLength={200}
            placeholder="Слово соратникам (до 200 знаков)…"
            style={{
              flex: 1,
              padding: "10px 14px",
              background: "var(--bg-elevated)",
              border: "1px solid var(--border)",
              borderRadius: "var(--radius-sm)",
              color: "var(--fg)",
              fontSize: "var(--text-xs)",
            }}
          />
          <button
            type="button"
            onClick={handleSend}
            disabled={sending || cooldown > 0 || text.trim() === ""}
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 8,
              padding: "10px 20px",
              background: "var(--accent)",
              border: "none",
              borderRadius: "var(--radius-sm)",
              color: "var(--accent-on)",
              fontWeight: 700,
              fontSize: "var(--text-xs)",
              cursor: sending || cooldown > 0 || text.trim() === "" ? "default" : "pointer",
              transition: "all 0.15s ease",
            }}
          >
            <Send size={14} />
            {cooldown > 0 ? `${cooldown}с` : "Сказать"}
          </button>
        </div>
      </div>

      {/* Правая колонка: Имперские вести гильдий Тамриэля */}
      <div className="fantasy-window" style={{ padding: 26, display: "flex", flexDirection: "column" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
          <Scroll size={22} style={{ color: "var(--accent)" }} />
          <div>
            <h3 style={{ fontFamily: "var(--font-display)", fontSize: 20, fontWeight: 700, margin: 0, color: "var(--fg)" }}>
              Вести гильдий Тамриэля
            </h3>
            <div style={{ fontSize: 12, color: "var(--muted)" }}>Хроника великих свершений всех орденов</div>
          </div>
        </div>

        <div
          style={{
            maxHeight: 500,
            minHeight: 360,
            overflowY: "auto",
            display: "flex",
            flexDirection: "column",
            gap: 12,
            paddingRight: 6,
          }}
        >
          {news.length === 0 ? (
            <div style={{ textAlign: "center", color: "var(--muted)", fontSize: "var(--text-xs)", padding: "36px 0" }}>
              Имперские гонцы пока не доставили свежих донесений.
            </div>
          ) : (
            news.map((item, idx) => (
              <div
                key={item.id ?? idx}
                style={{
                  padding: "12px 14px",
                  background: "var(--surface-raised)",
                  border: "1px solid var(--border)",
                  borderRadius: "var(--radius-sm)",
                  display: "flex",
                  flexDirection: "column",
                  gap: 6,
                }}
              >
                <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", fontSize: 11, color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
                  <span style={{ color: "var(--accent)", fontWeight: 600 }}>{item.guild_name ? `«${item.guild_name}»` : "Имперская весть"}</span>
                  <span>{fmtDate(item.inserted_at || item.created_at)}</span>
                </div>
                <div style={{ fontSize: 13, color: "var(--fg)", lineHeight: 1.5 }}>
                  {item.text || item.title || "Событие гильдии"}
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  )
}

// ── Главный зал гильдии (полноэкранный оплот) ──────────────────────────────────
function GuildHome({
  detail,
  myRole,
  onLeft,
}: {
  detail: GuildDetail
  myRole: string
  onLeft: () => void
}) {
  const isLeader = myRole === "leader"
  const isOfficer = myRole === "leader" || myRole === "officer"
  const [activeTab, setActiveTab] = useState<"altar" | "shop" | "roster" | "council">("altar")
  const [leaveModalOpen, setLeaveModalOpen] = useState(false)
  const [leaveBusy, setLeaveBusy] = useState(false)
  const [myUserId, setMyUserId] = useState<string | null>(null)

  const hero = useGameStore((s) => s.hero)
  const setHero = useGameStore((s) => s.setHero)

  useEffect(() => {
    api.getGuilds().then((r) => setMyUserId(r.my?.user_id ?? null)).catch(() => {})
  }, [])

  const guild = detail.guild
  const members = detail.members
  const buff = guild.buff
  const treasury = detail.treasury

  const refreshAll = async () => {
    onLeft()
    try {
      const fresh = await api.getHero()
      if (fresh?.hero) setHero(fresh.hero)
      else if (fresh?.id) setHero(fresh)
    } catch {}
  }

  const handleConfirmLeave = async () => {
    if (leaveBusy) return
    setLeaveBusy(true)
    try {
      await api.leaveGuild(guild.id)
      setLeaveModalOpen(false)
      onLeft()
    } catch {
      setLeaveModalOpen(false)
    } finally {
      setLeaveBusy(false)
    }
  }

  const nextExp = guild.exp_to_next ?? 0
  const expPct = nextExp > 0 ? Math.min(100, Math.round((guild.exp / nextExp) * 100)) : 100

  return (
    <div className="anim-fade-up" style={{ width: "100%", paddingBottom: 48 }}>
      {leaveModalOpen && (
        <LeaveConfirmModal
          isLeader={isLeader}
          onConfirm={handleConfirmLeave}
          onCancel={() => setLeaveModalOpen(false)}
          busy={leaveBusy}
        />
      )}

      {/* Величественное знамя Оплота на всю ширину */}
      <div className="guild-bastion-banner">
        <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: 24, justifyContent: "space-between" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 20, minWidth: 320, flex: 1 }}>
            <div className="guild-emblem-crest">
              {guild.emblem}
            </div>

            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
                <h1 className="guild-title-hero">{guild.name}</h1>
                <span
                  className={`guild-role-badge ${
                    isLeader ? "role-leader" : isOfficer ? "role-officer" : "role-member"
                  }`}
                >
                  {isLeader && <Crown size={12} />}
                  {isOfficer && !isLeader && <Shield size={12} />}
                  {GUILD_ROLE_RU[myRole] || myRole}
                </span>
              </div>

              {guild.motto && (
                <div className="guild-motto-ribbon">«{guild.motto}»</div>
              )}

              {/* Бафы гильдии */}
              {buff && (
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 10 }}>
                  <span className="guild-buff-chip">
                    ✨ Опыт: <strong>+{Math.round(buff.xp_mult * 100)}%</strong>
                  </span>
                  <span className="guild-buff-chip">
                    ⚔️ Атака: <strong>+{buff.attack_flat}</strong>
                  </span>
                  <span className="guild-buff-chip">
                    🛡️ Здоровье: <strong>+{buff.hp_flat}</strong>
                  </span>
                </div>
              )}
            </div>
          </div>

          {/* Правая секция: шкала опыта, статус пира, кнопка выхода */}
          <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 12 }}>
            <button
              onClick={() => setLeaveModalOpen(true)}
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 6,
                padding: "7px 14px",
                background: "var(--surface)",
                border: "1px solid var(--border)",
                borderRadius: "var(--radius-sm)",
                color: "var(--muted)",
                fontSize: 12,
                cursor: "pointer",
                transition: "all 0.15s ease",
              }}
              title={isLeader ? "Сложить полномочия и передать знамя" : "Покинуть ряды гильдии"}
            >
              <LogOut size={13} />
              {isLeader ? "Сложить знамя" : "Покинуть"}
            </button>

            {/* Баннер активного пира */}
            {treasury?.feast_active && (
              <div className="guild-feast-banner">
                <Beer size={15} />
                Пир соратников: +5% опыта
              </div>
            )}

            {/* Прогресс уровня гильдии */}
            <div className="guild-exp-container">
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12, fontFamily: "var(--font-mono)" }}>
                <span style={{ color: "var(--gold)", fontWeight: 700 }}>Ранг {guild.level}</span>
                <span style={{ color: "var(--muted)" }}>
                  {guild.level >= (guild.max_level ?? 20) ? "Макс. ранг" : `${fmt(guild.exp)} / ${fmt(guild.exp_to_next)} XP`}
                </span>
              </div>
              <div className="guild-exp-track">
                <div className="guild-exp-fill" style={{ width: `${expPct}%` }} />
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Навигация по залам гильдии */}
      <nav className="guild-chambers-nav" aria-label="Залы гильдии">
        <button
          onClick={() => setActiveTab("altar")}
          className={`guild-chamber-tab ${activeTab === "altar" ? "active" : ""}`}
        >
          <Flame size={17} />
          Алтарь и Казна
        </button>

        <button
          onClick={() => setActiveTab("shop")}
          className={`guild-chamber-tab ${activeTab === "shop" ? "active" : ""}`}
        >
          <ShoppingBag size={17} />
          Лавка соратников
        </button>

        <button
          onClick={() => setActiveTab("roster")}
          className={`guild-chamber-tab ${activeTab === "roster" ? "active" : ""}`}
        >
          <Users size={17} />
          Зал соратников
          <span className="guild-tab-badge">{members.length}</span>
        </button>

        <button
          onClick={() => setActiveTab("council")}
          className={`guild-chamber-tab ${activeTab === "council" ? "active" : ""}`}
        >
          <MessageSquare size={17} />
          Ратуша и Вести
        </button>
      </nav>

      {/* Контент активного зала */}
      {activeTab === "altar" && (
        <AltarAndTreasuryChamber detail={detail} heroGold={hero?.gold ?? 0} onChanged={refreshAll} />
      )}

      {activeTab === "shop" && <ShopChamber />}

      {activeTab === "roster" && (
        <RosterAndAppsChamber
          guildId={guild.id}
          members={members}
          myRole={myRole}
          isLeader={isLeader}
          onChanged={refreshAll}
        />
      )}

      {activeTab === "council" && (
        <CouncilAndNewsChamber guildId={guild.id} myUserId={myUserId} />
      )}
    </div>
  )
}

// ── Главная страница GuildPage ───────────────────────────────────────────────
export function GuildPage() {
  const hero = useGameStore((s) => s.hero)
  const [guilds, setGuilds] = useState<GuildSummary[]>([])
  const [my, setMy] = useState<{ guild_id: string; role: string } | null>(null)
  const [detail, setDetail] = useState<GuildDetail | null>(null)
  const [loading, setLoading] = useState(true)

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const res = await api.getGuilds()
      setGuilds(res.guilds || [])
      setMy(res.my ? { guild_id: res.my.guild_id, role: res.my.role } : null)
      setDetail(res.my ? await api.getGuild(res.my.guild_id) : null)
    } catch {
      setGuilds([])
      setMy(null)
      setDetail(null)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  const join = async (id: string): Promise<boolean | "pending"> => {
    try {
      const res = await api.joinGuild(id)
      if (res?.status === "application_pending") return "pending"
      await fetchData()
      return true
    } catch {
      return false
    }
  }

  if (loading) {
    return (
      <div style={{ textAlign: "center", padding: "80px 20px", color: "var(--muted)", fontSize: "var(--text-sm)" }}>
        <div style={{ fontSize: 36, marginBottom: 14 }}>🛡️</div>
        Знамёна соратников разворачиваются…
      </div>
    )
  }

  return detail && my ? (
    <GuildHome key={detail.guild.id} detail={detail} myRole={my.role} onLeft={fetchData} />
  ) : (
    <GuildLanding guilds={guilds} heroGold={hero?.gold ?? 0} onJoin={join} onCreated={fetchData} />
  )
}

import { useState } from "react"
import { api } from "@/lib/api"
import { useGameStore } from "@/stores/gameStore"
import { Feather, Key, Mail, Scroll, ArrowLeft } from "lucide-react"

interface AuthPageProps {
  initialMode?: "login" | "register"
  onBack?: () => void
}

export function AuthPage({ initialMode = "login", onBack }: AuthPageProps) {
  const [mode, setMode] = useState<"login" | "register">(initialMode)
  const [username, setUsername] = useState("")
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [error, setError] = useState("")
  const [loading, setLoading] = useState(false)
  const setAuthenticated = useGameStore((s) => s.setAuthenticated)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")
    setLoading(true)
    try {
      if (mode === "register") await api.register(username, email, password)
      await api.login(username, password)
      setAuthenticated(true)
    } catch (err: any) {
      setError(err.message || "Ошибка авторизации")
    } finally {
      setLoading(false)
    }
  }

  const labelStyle: React.CSSProperties = {
    fontSize: 11,
    fontFamily: "var(--font-mono)",
    color: "var(--accent)",
    textTransform: "uppercase",
    letterSpacing: "0.12em",
    marginBottom: 6,
    display: "block",
  }

  const inputContainerStyle: React.CSSProperties = {
    position: "relative",
    display: "flex",
    alignItems: "center",
  }

  const inputStyle: React.CSSProperties = {
    width: "100%",
    padding: "10px 36px 10px 4px",
    background: "transparent",
    border: "none",
    borderBottom: "1px solid color-mix(in srgb, var(--border) 70%, var(--accent) 30%)",
    borderRadius: 0,
    fontSize: 14,
    color: "var(--fg)",
    fontFamily: "var(--font-body)",
    outline: "none",
    transition: "border-color 0.2s ease",
  }

  return (
    <div
      style={{
        minHeight: "100vh",
        position: "relative",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "var(--bg)",
        padding: "24px 16px",
        overflow: "hidden",
      }}
    >
      {/* ─── Atmospheric Scriptorium Backdrop ───────────────────────────── */}
      <div style={{ position: "absolute", inset: 0, zIndex: 0, overflow: "hidden" }}>
        <img
          src="https://lh3.googleusercontent.com/aida-public/AB6AXuAAxJ4l6NHC74-BukPtvsZm7unR22dEAdIIYPI9GZ5D6d51BXNBI3QuVKQrz5Xe3oAxPS20DjrOZtXdSDblNJTD0mZq9lx8z1GNfTP9f4dEXMZAMy0cdMMmXHMLybf6UTnbLdUGI94E6l_Y81PgyTJzGzkwFrG1OyuqHkIu7Af3mWZyX6tPmS9HocjYQ1FCLhbB2Ix38cjAkw-JEAhWZqa-9aiRaaDmgVNZ8DDocj4c_57MDt9diNhi7WW7ungXsmyS3o39odnT6u0"
          alt="Ancient library scrolls lit by flickering candlelight"
          style={{
            width: "100%",
            height: "100%",
            objectFit: "cover",
            opacity: 0.22,
            filter: "brightness(0.6) blur(2px)",
            transform: "scale(1.05)",
          }}
        />
        <div
          style={{
            position: "absolute",
            inset: 0,
            background: "radial-gradient(circle at center, transparent 20%, var(--bg) 85%)",
          }}
        />
      </div>

      {/* ─── Main Card ─────────────────────────────────────────────────── */}
      <div
        style={{
          position: "relative",
          zIndex: 10,
          width: 440,
          maxWidth: "92vw",
        }}
        className="anim-fade-up"
      >
        {onBack && (
          <button
            onClick={onBack}
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 8,
              background: "transparent",
              border: "none",
              color: "var(--muted)",
              fontFamily: "var(--font-mono)",
              fontSize: 12,
              letterSpacing: "0.08em",
              textTransform: "uppercase",
              cursor: "pointer",
              marginBottom: 16,
              transition: "color 0.15s ease",
            }}
            onMouseEnter={(e) => (e.currentTarget.style.color = "var(--accent)")}
            onMouseLeave={(e) => (e.currentTarget.style.color = "var(--muted)")}
          >
            <ArrowLeft size={14} />
            Вернуться к обзору
          </button>
        )}

        <div
          className="stone-card parchment-glow"
          style={{
            borderRadius: "var(--radius-lg)",
            padding: "36px 32px",
            background: "color-mix(in srgb, var(--surface) 95%, black)",
            border: "1px solid color-mix(in srgb, var(--accent) 30%, var(--border))",
          }}
        >
          {/* Card Title / Seal */}
          <div style={{ textAlign: "center", marginBottom: 28 }}>
            <div
              style={{
                width: 48,
                height: 48,
                borderRadius: "var(--radius-pill)",
                background: "color-mix(in srgb, var(--surface-raised) 90%, black)",
                border: "1px solid color-mix(in srgb, var(--accent) 40%, transparent)",
                display: "inline-flex",
                alignItems: "center",
                justifyContent: "center",
                color: "var(--accent)",
                marginBottom: 12,
              }}
            >
              <Scroll size={22} />
            </div>
            <h1
              style={{
                fontFamily: "var(--font-display)",
                fontSize: 28,
                fontStyle: "italic",
                fontWeight: 700,
                letterSpacing: "-0.01em",
                color: "var(--fg)",
                marginBottom: 4,
              }}
            >
              {mode === "login" ? "Доступ к Летописи" : "Внесение в Летопись"}
            </h1>
            <p
              style={{
                fontFamily: "var(--font-mono)",
                fontSize: 10,
                letterSpacing: "0.15em",
                textTransform: "uppercase",
                color: "var(--muted)",
              }}
            >
              Имперские Архивы Скайрима
            </p>
          </div>

          {/* Mode Switcher */}
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "1fr 1fr",
              gap: 4,
              padding: 4,
              background: "var(--bg)",
              borderRadius: "var(--radius-sm)",
              border: "1px solid var(--border)",
              marginBottom: 28,
            }}
          >
            <button
              type="button"
              onClick={() => { setMode("login"); setError("") }}
              style={{
                padding: "8px 12px",
                border: "none",
                borderRadius: "var(--radius-sm)",
                fontFamily: "var(--font-mono)",
                fontSize: 11,
                letterSpacing: "0.06em",
                textTransform: "uppercase",
                cursor: "pointer",
                transition: "all 0.15s ease",
                background: mode === "login" ? "var(--surface-raised)" : "transparent",
                color: mode === "login" ? "var(--accent)" : "var(--muted)",
                fontWeight: mode === "login" ? 600 : 400,
                boxShadow: mode === "login" ? "0 2px 8px rgba(0,0,0,0.3)" : "none",
              }}
            >
              Войти в архив
            </button>
            <button
              type="button"
              onClick={() => { setMode("register"); setError("") }}
              style={{
                padding: "8px 12px",
                border: "none",
                borderRadius: "var(--radius-sm)",
                fontFamily: "var(--font-mono)",
                fontSize: 11,
                letterSpacing: "0.06em",
                textTransform: "uppercase",
                cursor: "pointer",
                transition: "all 0.15s ease",
                background: mode === "register" ? "var(--surface-raised)" : "transparent",
                color: mode === "register" ? "var(--accent)" : "var(--muted)",
                fontWeight: mode === "register" ? 600 : 400,
                boxShadow: mode === "register" ? "0 2px 8px rgba(0,0,0,0.3)" : "none",
              }}
            >
              Новое имя
            </button>
          </div>

          {/* Form */}
          <form onSubmit={handleSubmit} style={{ display: "flex", flexDirection: "column", gap: 20 }}>
            <div>
              <label htmlFor="auth-username" style={labelStyle}>
                Имя летописца
              </label>
              <div style={inputContainerStyle}>
                <input
                  id="auth-username"
                  name="username"
                  type="text"
                  placeholder="Введи своё имя..."
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  autoComplete="username"
                  spellCheck={false}
                  required
                  style={inputStyle}
                  onFocus={(e) => (e.target.style.borderBottomColor = "var(--accent)")}
                  onBlur={(e) => (e.target.style.borderBottomColor = "color-mix(in srgb, var(--border) 70%, var(--accent) 30%)")}
                />
                <Feather size={15} style={{ position: "absolute", right: 8, color: "var(--muted)", opacity: 0.6 }} />
              </div>
            </div>

            {mode === "register" && (
              <div>
                <label htmlFor="auth-email" style={labelStyle}>
                  Свиток почты
                </label>
                <div style={inputContainerStyle}>
                  <input
                    id="auth-email"
                    name="email"
                    type="email"
                    placeholder="почта@тамриэль.ру"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    autoComplete="email"
                    spellCheck={false}
                    required
                    style={inputStyle}
                    onFocus={(e) => (e.target.style.borderBottomColor = "var(--accent)")}
                    onBlur={(e) => (e.target.style.borderBottomColor = "color-mix(in srgb, var(--border) 70%, var(--accent) 30%)")}
                  />
                  <Mail size={15} style={{ position: "absolute", right: 8, color: "var(--muted)", opacity: 0.6 }} />
                </div>
              </div>
            )}

            <div>
              <label htmlFor="auth-password" style={labelStyle}>
                Тайное слово
              </label>
              <div style={inputContainerStyle}>
                <input
                  id="auth-password"
                  name="password"
                  type="password"
                  placeholder="••••••••"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  autoComplete={mode === "register" ? "new-password" : "current-password"}
                  required
                  style={inputStyle}
                  onFocus={(e) => (e.target.style.borderBottomColor = "var(--accent)")}
                  onBlur={(e) => (e.target.style.borderBottomColor = "color-mix(in srgb, var(--border) 70%, var(--accent) 30%)")}
                />
                <Key size={15} style={{ position: "absolute", right: 8, color: "var(--muted)", opacity: 0.6 }} />
              </div>
            </div>

            {error && (
              <div
                role="alert"
                style={{
                  color: "var(--danger)",
                  fontSize: 13,
                  textAlign: "center",
                  padding: "8px 12px",
                  borderRadius: "var(--radius-sm)",
                  background: "color-mix(in srgb, var(--danger) 12%, transparent)",
                  border: "1px solid color-mix(in srgb, var(--danger) 30%, transparent)",
                }}
              >
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              style={{
                width: "100%",
                padding: "13px 20px",
                marginTop: 6,
                background: "var(--accent)",
                color: "var(--accent-on)",
                borderRadius: "var(--radius-sm)",
                fontWeight: 600,
                fontSize: 13,
                fontFamily: "var(--font-mono)",
                textTransform: "uppercase",
                letterSpacing: "0.12em",
                border: "none",
                cursor: loading ? "wait" : "pointer",
                opacity: loading ? 0.6 : 1,
                boxShadow: "0 0 24px color-mix(in srgb, var(--accent) 35%, transparent)",
                transition: "all 0.2s ease",
              }}
              onMouseEnter={(e) => {
                if (!loading) {
                  e.currentTarget.style.transform = "translateY(-1px)"
                  e.currentTarget.style.boxShadow = "0 0 32px color-mix(in srgb, var(--accent) 50%, transparent)"
                }
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.transform = "translateY(0)"
                e.currentTarget.style.boxShadow = "0 0 24px color-mix(in srgb, var(--accent) 35%, transparent)"
              }}
            >
              {loading
                ? "Проверка свитков…"
                : mode === "login"
                ? "Подтвердить личность"
                : "Закрепить имя в архивах"}
            </button>
          </form>
        </div>
      </div>
    </div>
  )
}

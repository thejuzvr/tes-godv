import { useEffect, useState, Component, type ReactNode } from "react"
import { BrowserRouter, Routes, Route, Link, useLocation } from "react-router-dom"
import { Moon, Sun } from "lucide-react"
import "./realm-shell.css"
import "./pages/dashboard-skin.css"
import { useGameStore } from "@/stores/gameStore"
import { api } from "@/lib/api"
import { useWebSocket } from "@/hooks/useWebSocket"
import { AuthPage } from "@/pages/AuthPage"
import { LandingPage } from "@/pages/LandingPage"
import { CreateHeroPage } from "@/pages/CreateHeroPage"
import { DashboardPage } from "@/pages/DashboardPage"
import { MapPage } from "@/pages/MapPage"
import { GuildPage } from "@/pages/GuildPage"
import { AdminPage } from "@/pages/AdminPage"
import { PantheonPage } from "@/components/pantheon/PantheonPage"
import { AnalyticsPage } from "@/pages/AnalyticsPage"
import { CharacterLayout, PassportPage, SkillsPage } from "@/pages/CharacterPages"
import { GearPage } from "@/pages/GearPage"
import { WikiPage } from "@/pages/WikiPage"
import { NarrativesPage } from "@/pages/NarrativesPage"
import { NotFoundPage, ServerErrorPage } from "@/pages/ErrorPages"

// Initialize theme before first paint (dark «Ночной уголь» by default)
const initialTheme = localStorage.getItem("theme") || "dark"
document.documentElement.setAttribute("data-theme", initialTheme)

/** Error boundary: крэш рендера → TES «экран смерти» вместо белого экрана. */
class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null }

  static getDerivedStateFromError(error: Error) {
    return { error }
  }

  render() {
    if (this.state.error) {
      return <ServerErrorPage detail={this.state.error.message} />
    }
    return this.props.children
  }
}

function TopBar() {
  const location = useLocation()
  const logout = useGameStore((s) => s.logout)
  const hero = useGameStore((s) => s.hero)
  const isAdmin = useGameStore((s) => s.isAdmin)
  const wsConnected = useGameStore((s) => s.wsConnected)
  const [theme, setTheme] = useState<string>(initialTheme)

  const toggleTheme = () => {
    const next = theme === "dark" ? "light" : "dark"
    setTheme(next)
    document.documentElement.setAttribute("data-theme", next)
    localStorage.setItem("theme", next)
    window.dispatchEvent(new Event("resize")) // canvas-панели перерисовываются под тему
  }

  return (
    <header className="top-bar">
      <div className="logo">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2L2 7l10 5 10-5-10-5z"/><path d="M2 17l10 5 10-5"/><path d="M2 12l10 5 10-5"/></svg>
        TES Idle
      </div>
      <nav className="nav-pills">
        <Link to="/" className={`nav-pill ${location.pathname === "/" ? "active" : ""}`}>Панель</Link>
        <Link to="/map" className={`nav-pill ${location.pathname === "/map" ? "active" : ""}`}>Карта</Link>
        <div className={`nav-menu ${location.pathname.startsWith("/character") || location.pathname === "/analytics" ? "active" : ""}`}>
          <Link to="/character" className="nav-pill">Персонаж</Link>
          <div className="nav-submenu" role="menu">
            <Link to="/character" role="menuitem">Паспорт</Link>
            <Link to="/character/skills" role="menuitem">Навыки</Link>
            <Link to="/character/gear" role="menuitem">Снаряжение</Link>
            <Link to="/analytics" role="menuitem">Аналитика</Link>
          </div>
        </div>
        <Link to="/guild" className={`nav-pill ${location.pathname === "/guild" ? "active" : ""}`}>Гильдия</Link>
        <Link to="/pantheon" className={`nav-pill ${location.pathname === "/pantheon" ? "active" : ""}`}>Пантеон</Link>
        <Link to="/wiki" className={`nav-pill ${location.pathname === "/wiki" ? "active" : ""}`}>Wiki</Link>
        {isAdmin && <Link to="/admin" className={`nav-pill ${location.pathname === "/admin" ? "active" : ""}`}>Админ</Link>}
      </nav>
      <div style={{ display: "flex", alignItems: "center", gap: "var(--space-3)" }}>
        {hero && (
          <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)" }}>
            <span className={`status-dot ${wsConnected ? "" : "offline"}`} />
            {wsConnected ? "Герой действует" : "Переподключение…"}
          </span>
        )}
        <button onClick={logout} className="nav-pill" style={{ color: "var(--muted)" }}>Выйти</button>
        <button onClick={toggleTheme} className="nav-pill" style={{ color: "var(--muted)", display: "inline-flex", alignItems: "center" }} aria-label={theme === "dark" ? "Светлая тема" : "Тёмная тема"} title={theme === "dark" ? "Свет «Пергамент»" : "Тьма «Ночной уголь»"}>
          {theme === "dark" ? <Sun size={15} /> : <Moon size={15} />}
        </button>
      </div>
    </header>
  )
}

function StatusBar() {
  const hero = useGameStore((s) => s.hero)
  const wsConnected = useGameStore((s) => s.wsConnected)
  if (!hero) return null
  const gph = Math.floor(hero.total_gold_earned / Math.max(1, hero.total_play_time_seconds / 3600))
  return (
    <footer className="status-bar">
      <div className="status-left">
        <span><span className={`status-dot ${wsConnected ? "" : "offline"}`} />{wsConnected ? "Подключено" : "Офлайн"}</span>
        <span>Золото/ч: +{gph}</span>
      </div>
      <div className="status-right">
        <span>Автономный режим · Герой действует сам</span>
      </div>
    </footer>
  )
}

// Известные маршруты — на них действуют правила авторизации (AuthPage/CreateHero/
// AppLayout). Всё остальное — 404 «Разыскивается страница» показывается ВСЕМ,
// включая гостей: путь не станет существовать после входа.
const KNOWN_PATHS = ["/", "/map", "/guild", "/pantheon", "/analytics", "/character", "/character/skills", "/character/gear", "/narratives", "/wiki", "/admin"]

function AppLayout() {
  const { isAuthenticated, hero, setHero, setLoading, setAdmin, setWsConnected } = useGameStore()
  const [checking, setChecking] = useState(true)
  const [authMode, setAuthMode] = useState<"login" | "register" | null>(null)
  const route = useLocation()
  const token = api.getToken()
  const { connected, on: onWs } = useWebSocket(token, hero?.id || null)

  // Sync WebSocket state to store
  useEffect(() => {
    setWsConnected(connected)
  }, [connected, setWsConnected])

  useEffect(() => {
    if (!isAuthenticated) { setChecking(false); return }

    // Тихая проверка роли (200 для всех) — без 403-шума в консоли
    api.getMe().then((u) => setAdmin(!!u.is_admin)).catch(() => setAdmin(false))

    // Load hero
    api.getHero().then(setHero).catch(() => setHero(null)).finally(() => { setChecking(false); setLoading(false) })
  }, [isAuthenticated, setHero, setLoading, setAdmin])

  // Mark offline on page unload
  useEffect(() => {
    if (!isAuthenticated) return
    const handleBeforeUnload = () => {
      navigator.sendBeacon("/api/v1/hero/offline")
    }
    window.addEventListener("beforeunload", handleBeforeUnload)
    return () => window.removeEventListener("beforeunload", handleBeforeUnload)
  }, [isAuthenticated])

  // 404 до auth-гейта: неизвестный путь не зависит от входа/героя
  const path = route.pathname.replace(/\/+$/, "") || "/"
  if (!KNOWN_PATHS.includes(path)) return <NotFoundPage />

  if (!isAuthenticated) {
    if (authMode) {
      return <AuthPage initialMode={authMode} onBack={() => setAuthMode(null)} />
    }
    return <LandingPage onOpenAuth={(mode) => setAuthMode(mode)} />
  }
  if (checking) return <div className="dashboard"><div style={{ textAlign: "center", color: "var(--muted)", padding: 48 }}>Загрузка…</div></div>
  if (!hero) return <CreateHeroPage />

  return (
    <div className={`dashboard ${path.startsWith("/character") || ["/guild", "/analytics", "/pantheon", "/wiki", "/admin", "/narratives"].includes(path) ? "realm-shell" : ""} ${route.pathname === "/" ? "observatory" : ""} ${route.pathname === "/map" ? "map-shell" : ""} ${route.pathname === "/wiki" ? "wiki-shell" : ""} ${route.pathname === "/admin" ? "admin-shell" : ""}`}>
      <TopBar />
      <Routes>
        <Route path="/" element={<DashboardPage onWs={onWs} />} />
        <Route path="/map" element={<MapPage onWs={onWs} />} />
        <Route path="/guild" element={<GuildPage />} />
        <Route path="/pantheon" element={<PantheonPage />} />
        <Route path="/character" element={<CharacterLayout />}>
          <Route index element={<PassportPage />} />
          <Route path="skills" element={<SkillsPage />} />
          <Route path="gear" element={<GearPage />} />
        </Route>
        <Route path="/analytics" element={<AnalyticsPage />} />
        <Route path="/narratives" element={<NarrativesPage />} />
        <Route path="/wiki" element={<WikiPage />} />
        <Route path="/admin" element={<AdminPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Routes>
      <StatusBar />
    </div>
  )
}

export default function App() {
  return (
    <ErrorBoundary>
      <BrowserRouter>
        <AppLayout />
      </BrowserRouter>
    </ErrorBoundary>
  )
}

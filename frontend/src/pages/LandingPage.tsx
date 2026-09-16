import { useState } from "react"
import { Sun, Moon, Swords, Sparkles, BookOpen, Compass, Shield, Scroll } from "lucide-react"

interface LandingPageProps {
  onOpenAuth: (mode: "login" | "register") => void
}

export function LandingPage({ onOpenAuth }: LandingPageProps) {
  const [theme, setTheme] = useState<string>(() => localStorage.getItem("theme") || "dark")

  const toggleTheme = () => {
    const next = theme === "dark" ? "light" : "dark"
    setTheme(next)
    document.documentElement.setAttribute("data-theme", next)
    localStorage.setItem("theme", next)
    window.dispatchEvent(new Event("resize"))
  }

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", color: "var(--fg)", display: "flex", flexDirection: "column" }}>
      {/* ─── Top Navigation Bar ────────────────────────────────────────── */}
      <header
        style={{
          position: "fixed",
          top: 0,
          left: 0,
          right: 0,
          zIndex: 50,
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "16px 32px",
          background: "color-mix(in srgb, var(--bg) 85%, transparent)",
          backdropFilter: "blur(12px)",
          borderBottom: "1px solid color-mix(in srgb, var(--border) 70%, transparent)",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <div
            style={{
              width: 34,
              height: 34,
              borderRadius: "var(--radius-sm)",
              background: "var(--surface)",
              border: "1px solid var(--accent)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: "var(--accent)",
            }}
          >
            <Scroll size={18} />
          </div>
          <div>
            <span
              style={{
                fontFamily: "var(--font-display)",
                fontSize: 20,
                fontWeight: 700,
                letterSpacing: "0.05em",
                color: "var(--accent)",
                fontStyle: "italic",
              }}
            >
              TES Idle
            </span>
            <span
              style={{
                display: "block",
                fontFamily: "var(--font-mono)",
                fontSize: 9,
                letterSpacing: "0.15em",
                textTransform: "uppercase",
                color: "var(--muted)",
              }}
            >
              The Imperial Chronicler
            </span>
          </div>
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <button
            onClick={toggleTheme}
            className="nav-pill"
            style={{ color: "var(--muted)", display: "inline-flex", alignItems: "center", padding: "6px 12px" }}
            aria-label={theme === "dark" ? "Светлая тема" : "Тёмная тема"}
            title={theme === "dark" ? "Свет «Пергамент»" : "Тьма «Ночной уголь»"}
          >
            {theme === "dark" ? <Sun size={15} /> : <Moon size={15} />}
          </button>
          <button
            onClick={() => onOpenAuth("login")}
            className="nav-pill"
            style={{
              fontFamily: "var(--font-mono)",
              fontSize: "var(--text-xs)",
              textTransform: "uppercase",
              letterSpacing: "0.08em",
              color: "var(--fg)",
              border: "1px solid var(--border)",
              padding: "7px 18px",
            }}
          >
            Войти
          </button>
          <button
            onClick={() => onOpenAuth("register")}
            style={{
              fontFamily: "var(--font-mono)",
              fontSize: "var(--text-xs)",
              textTransform: "uppercase",
              letterSpacing: "0.08em",
              fontWeight: 600,
              background: "var(--accent)",
              color: "var(--accent-on)",
              border: "none",
              borderRadius: "var(--radius-sm)",
              padding: "8px 20px",
              cursor: "pointer",
              boxShadow: "0 0 18px color-mix(in srgb, var(--accent) 30%, transparent)",
              transition: "transform 0.15s ease",
            }}
            onMouseEnter={(e) => (e.currentTarget.style.transform = "scale(1.03)")}
            onMouseLeave={(e) => (e.currentTarget.style.transform = "scale(1)")}
          >
            Начать сагу
          </button>
        </div>
      </header>

      {/* ─── Hero Section ──────────────────────────────────────────────── */}
      <section
        style={{
          position: "relative",
          minHeight: "88vh",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          padding: "120px 24px 60px",
          overflow: "hidden",
        }}
      >
        {/* Background Artwork */}
        <div
          style={{
            position: "absolute",
            inset: 0,
            zIndex: 0,
            overflow: "hidden",
          }}
        >
          <img
            src="https://lh3.googleusercontent.com/aida-public/AB6AXuAZfbltgdSGTCZvEiTHvBpJp_N4-5DhbXpTbjZubRY0KTWMHU5awqXTL16nXiM11C0JAURc50PiTEzZ9zE0qCVKVpPg8HplnaN_YynLA326Y6YbpuwJniXfaL7cws7jTXqDyN--ZvuSD2TJ5wsBWgV6wMkWIYsCC5wOpDHa_kRo2tMPsSu_ZYklfhLtbRD_didc_qH3ZIVJaD5cK6zPYCZnCXlVnrRvWOCaZZS52BxwVmKrSXdg6nNboHKc7sPg_Ekz3C_bI6IgajQ"
            alt="Colossal dragon soaring above ancient snow-dusted nord ruins in Tamriel twilight"
            className="hero-mask"
            style={{
              width: "100%",
              height: "100%",
              objectFit: "cover",
              opacity: 0.38,
              transform: "scale(1.05)",
            }}
          />
          <div
            style={{
              position: "absolute",
              inset: 0,
              background: "linear-gradient(to top, var(--bg) 15%, transparent 60%, var(--bg) 100%)",
            }}
          />
        </div>

        {/* Hero Content */}
        <div
          style={{
            position: "relative",
            zIndex: 10,
            maxWidth: 900,
            textAlign: "center",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
          }}
          className="anim-fade-up"
        >
          <div
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 8,
              padding: "6px 16px",
              borderRadius: "var(--radius-pill)",
              background: "color-mix(in srgb, var(--surface) 80%, transparent)",
              border: "1px solid color-mix(in srgb, var(--accent) 30%, transparent)",
              marginBottom: 24,
            }}
          >
            <Sparkles size={14} color="var(--accent)" />
            <span
              style={{
                fontFamily: "var(--font-mono)",
                fontSize: 11,
                letterSpacing: "0.12em",
                textTransform: "uppercase",
                color: "var(--accent)",
              }}
            >
              Zero-Player RPG · Сеттинг The Elder Scrolls
            </span>
          </div>

          <h1
            className="text-glow"
            style={{
              fontFamily: "var(--font-display)",
              fontSize: "clamp(38px, 6vw, 76px)",
              fontWeight: 700,
              lineHeight: 1.08,
              fontStyle: "italic",
              color: "var(--fg)",
              marginBottom: 24,
              letterSpacing: "-0.01em",
            }}
          >
            Свидетель легенды.<br />
            <span style={{ color: "var(--accent)" }}>Без лишних усилий.</span>
          </h1>

          <p
            style={{
              fontSize: "clamp(15px, 2vw, 19px)",
              color: "var(--muted)",
              lineHeight: 1.6,
              maxWidth: 680,
              marginBottom: 36,
              fontFamily: "var(--font-body)",
            }}
          >
            Твой подопечный бродит по просторам Скайрима, зачищает курганы, торгуется с купцами и пьёт в тавернах сам. 
            Ты — его божественный покровитель, направляющий его судьбу через летопись Тамриэля.
          </p>

          <div style={{ display: "flex", flexWrap: "wrap", gap: 16, justifyContent: "center" }}>
            <button
              onClick={() => onOpenAuth("register")}
              style={{
                padding: "14px 36px",
                fontSize: 14,
                fontFamily: "var(--font-mono)",
                fontWeight: 600,
                letterSpacing: "0.08em",
                textTransform: "uppercase",
                background: "var(--accent)",
                color: "var(--accent-on)",
                borderRadius: "var(--radius-sm)",
                border: "none",
                cursor: "pointer",
                boxShadow: "0 0 30px color-mix(in srgb, var(--accent) 40%, transparent)",
                transition: "all 0.2s ease",
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.transform = "translateY(-2px)"
                e.currentTarget.style.boxShadow = "0 0 40px color-mix(in srgb, var(--accent) 55%, transparent)"
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.transform = "translateY(0)"
                e.currentTarget.style.boxShadow = "0 0 30px color-mix(in srgb, var(--accent) 40%, transparent)"
              }}
            >
              Создать героя
            </button>
            <button
              onClick={() => onOpenAuth("login")}
              style={{
                padding: "14px 32px",
                fontSize: 14,
                fontFamily: "var(--font-mono)",
                letterSpacing: "0.08em",
                textTransform: "uppercase",
                background: "transparent",
                color: "var(--fg)",
                borderRadius: "var(--radius-sm)",
                border: "1px solid color-mix(in srgb, var(--border) 80%, var(--accent) 20%)",
                cursor: "pointer",
                transition: "all 0.2s ease",
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.borderColor = "var(--accent)"
                e.currentTarget.style.background = "color-mix(in srgb, var(--surface) 60%, transparent)"
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.borderColor = "color-mix(in srgb, var(--border) 80%, var(--accent) 20%)"
                e.currentTarget.style.background = "transparent"
              }}
            >
              Войти в летопись
            </button>
          </div>
        </div>
      </section>

      {/* ─── Pillars Section ───────────────────────────────────────────── */}
      <section style={{ padding: "60px 24px 100px", maxWidth: 1200, margin: "0 auto", width: "100%" }}>
        <div style={{ textAlign: "center", marginBottom: 54 }}>
          <div className="gilded-divider" style={{ marginBottom: 16 }}>
            <span style={{ color: "var(--accent)", fontSize: 16 }}>◆</span>
          </div>
          <h2
            style={{
              fontFamily: "var(--font-display)",
              fontSize: 36,
              fontStyle: "italic",
              fontWeight: 700,
              color: "var(--fg)",
              marginBottom: 10,
            }}
          >
            Три столпа вашего приключения
          </h2>
          <p style={{ color: "var(--muted)", fontSize: 15, fontFamily: "var(--font-body)" }}>
            Классическая механика Godville в эпической атмосфере Древних Свитков
          </p>
        </div>

        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(310px, 1fr))",
            gap: 24,
          }}
        >
          {/* Feature 1 */}
          <div
            className="stone-card parchment-glow"
            style={{
              padding: 32,
              borderRadius: "var(--radius-lg)",
              display: "flex",
              flexDirection: "column",
              gap: 16,
              transition: "transform 0.25s ease, border-color 0.25s ease",
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.transform = "translateY(-4px)"
              e.currentTarget.style.borderColor = "var(--accent)"
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.transform = "translateY(0)"
              e.currentTarget.style.borderColor = "color-mix(in srgb, var(--border) 75%, var(--accent) 25%)"
            }}
          >
            <div
              style={{
                width: 48,
                height: 48,
                borderRadius: "var(--radius-md)",
                background: "color-mix(in srgb, var(--accent) 15%, transparent)",
                color: "var(--accent)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <Compass size={24} />
            </div>
            <h3 style={{ fontFamily: "var(--font-display)", fontSize: 22, fontStyle: "italic", color: "var(--fg)" }}>
              Автономная жизнь
            </h3>
            <p style={{ color: "var(--muted)", fontSize: 14, lineHeight: 1.6 }}>
              Герой обладает уникальным геномом личности (BrainHash) и 9 чертами характера. Он сам оценивает нужды,
              выбирает цели через Utility AI, исследует руины, находит артефакты и прокачивается даже в ваше отсутствие.
            </p>
          </div>

          {/* Feature 2 */}
          <div
            className="stone-card parchment-glow"
            style={{
              padding: 32,
              borderRadius: "var(--radius-lg)",
              display: "flex",
              flexDirection: "column",
              gap: 16,
              transition: "transform 0.25s ease, border-color 0.25s ease",
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.transform = "translateY(-4px)"
              e.currentTarget.style.borderColor = "var(--accent)"
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.transform = "translateY(0)"
              e.currentTarget.style.borderColor = "color-mix(in srgb, var(--border) 75%, var(--accent) 25%)"
            }}
          >
            <div
              style={{
                width: 48,
                height: 48,
                borderRadius: "var(--radius-md)",
                background: "color-mix(in srgb, var(--danger) 15%, transparent)",
                color: "var(--danger)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <Sparkles size={24} />
            </div>
            <h3 style={{ fontFamily: "var(--font-display)", fontSize: 22, fontStyle: "italic", color: "var(--fg)" }}>
              Воля Божества
            </h3>
            <p style={{ color: "var(--muted)", fontSize: 14, lineHeight: 1.6 }}>
              Выступайте в роли Высшей Силы: вознаграждайте героя за подвиги, обрушивайте гнев молний на обидчиков,
              исцеляйте смертельные раны или меняйте погоду над провинцией ради удачной охоты.
            </p>
          </div>

          {/* Feature 3 */}
          <div
            className="stone-card parchment-glow"
            style={{
              padding: 32,
              borderRadius: "var(--radius-lg)",
              display: "flex",
              flexDirection: "column",
              gap: 16,
              transition: "transform 0.25s ease, border-color 0.25s ease",
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.transform = "translateY(-4px)"
              e.currentTarget.style.borderColor = "var(--accent)"
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.transform = "translateY(0)"
              e.currentTarget.style.borderColor = "color-mix(in srgb, var(--border) 75%, var(--accent) 25%)"
            }}
          >
            <div
              style={{
                width: 48,
                height: 48,
                borderRadius: "var(--radius-md)",
                background: "color-mix(in srgb, var(--xp) 15%, transparent)",
                color: "var(--xp)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <BookOpen size={24} />
            </div>
            <h3 style={{ fontFamily: "var(--font-display)", fontSize: 22, fontStyle: "italic", color: "var(--fg)" }}>
              Живой манускрипт
            </h3>
            <p style={{ color: "var(--muted)", fontSize: 14, lineHeight: 1.6 }}>
              Свыше 1190 нарративных шаблонов и многослойный генератор сцен (погода, воспоминания, причуды).
              Каждое событие пишется сочным слогом летописцев, скальдов и очевидцев Тамриэля.
            </p>
          </div>
        </div>
      </section>

      {/* ─── Chronicle Showcase Section ────────────────────────────────── */}
      <section
        style={{
          padding: "80px 24px",
          background: "color-mix(in srgb, var(--surface) 40%, var(--bg))",
          borderTop: "1px solid var(--border)",
          borderBottom: "1px solid var(--border)",
        }}
      >
        <div
          style={{
            maxWidth: 1100,
            margin: "0 auto",
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))",
            gap: 48,
            alignItems: "center",
          }}
        >
          <div>
            <div
              style={{
                display: "inline-block",
                fontFamily: "var(--font-mono)",
                fontSize: 11,
                letterSpacing: "0.15em",
                textTransform: "uppercase",
                color: "var(--accent)",
                marginBottom: 12,
              }}
            >
              Сердце интерфейса
            </div>
            <h2
              style={{
                fontFamily: "var(--font-display)",
                fontSize: "clamp(30px, 3.5vw, 42px)",
                fontStyle: "italic",
                fontWeight: 700,
                color: "var(--fg)",
                lineHeight: 1.15,
                marginBottom: 20,
              }}
            >
              Древний манускрипт, который пишется сам
            </h2>
            <p style={{ color: "var(--muted)", fontSize: 15, lineHeight: 1.7, marginBottom: 24 }}>
              Каждый шаг героя — от сбора горноцвета у дороги до победы над драконом — фиксируется в иллюминированной
              хронике. Записи объединяются в главы, отражают погоду мира и психологическое состояние персонажа.
            </p>

            <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <Shield size={18} color="var(--accent)" />
                <span style={{ fontSize: 14, color: "var(--fg)" }}>
                  Более 50 типов событий: сражения, кражи, сны, кузница, рыбалка
                </span>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <Swords size={18} color="var(--danger)" />
                <span style={{ fontSize: 14, color: "var(--fg)" }}>
                  Многораундовые бои с монстрами и боссами в реальном времени
                </span>
              </div>
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <Scroll size={18} color="var(--xp)" />
                <span style={{ fontSize: 14, color: "var(--fg)" }}>
                  Репутация во фракциях, законы ярлов и возможность попасть в тюрьму
                </span>
              </div>
            </div>
          </div>

          {/* Manuscript Card Preview */}
          <div
            className="stone-card parchment-glow"
            style={{
              padding: 32,
              borderRadius: "var(--radius-lg)",
              background: "var(--surface)",
              border: "1px solid color-mix(in srgb, var(--accent) 35%, var(--border))",
              position: "relative",
            }}
          >
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                borderBottom: "1px solid color-mix(in srgb, var(--accent) 20%, var(--border))",
                paddingBottom: 14,
                marginBottom: 18,
              }}
            >
              <span
                style={{
                  fontFamily: "var(--font-display)",
                  fontSize: 16,
                  fontStyle: "italic",
                  fontWeight: 600,
                  color: "var(--accent)",
                }}
              >
                День 142 Четвертой Эпохи · Ледяное безмолвие
              </span>
              <span
                style={{
                  fontFamily: "var(--font-mono)",
                  fontSize: 10,
                  color: "var(--muted)",
                  letterSpacing: "0.08em",
                }}
              >
                ВЫСОКИЙ ХРОТГАР
              </span>
            </div>

            <p
              style={{
                fontFamily: "var(--font-body)",
                fontStyle: "italic",
                fontSize: 15,
                lineHeight: 1.8,
                color: "var(--fg)",
                marginBottom: 20,
              }}
            >
              <span className="drop-cap">В</span>етры на Семи Тысячах Ступеней были особенно свирепы в этот полдень.
              Мой подопечный наткнулся на ледяного призрака близ святилища Кинарет. Вместо обнажённой стали он предпочёл
              применить хитрость и зелье бесшумных шагов. За скалистым выступом он подобрал древний нордский амулет...
            </p>

            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                paddingTop: 14,
                borderTop: "1px dashed var(--border)",
              }}
            >
              <div style={{ display: "flex", gap: 8 }}>
                <span
                  style={{
                    fontSize: 11,
                    fontFamily: "var(--font-mono)",
                    padding: "3px 8px",
                    borderRadius: "var(--radius-sm)",
                    background: "color-mix(in srgb, var(--danger) 15%, transparent)",
                    color: "var(--danger)",
                  }}
                >
                  Бой побеждён
                </span>
                <span
                  style={{
                    fontSize: 11,
                    fontFamily: "var(--font-mono)",
                    padding: "3px 8px",
                    borderRadius: "var(--radius-sm)",
                    background: "color-mix(in srgb, var(--gold) 15%, transparent)",
                    color: "var(--gold)",
                  }}
                >
                  +42🪙 золота
                </span>
              </div>
              <span
                style={{
                  fontFamily: "var(--font-mono)",
                  fontSize: 10,
                  color: "var(--muted)",
                  textTransform: "uppercase",
                  letterSpacing: "0.1em",
                }}
              >
                Летописец 4E
              </span>
            </div>
          </div>
        </div>
      </section>

      {/* ─── Call to Action Section ────────────────────────────────────── */}
      <section
        style={{
          padding: "100px 24px",
          textAlign: "center",
          maxWidth: 800,
          margin: "0 auto",
        }}
      >
        <div className="gilded-divider" style={{ marginBottom: 24 }}>
          <span style={{ color: "var(--accent)", fontSize: 18 }}>◆</span>
        </div>
        <h2
          style={{
            fontFamily: "var(--font-display)",
            fontSize: "clamp(32px, 4vw, 48px)",
            fontStyle: "italic",
            fontWeight: 700,
            color: "var(--fg)",
            marginBottom: 16,
          }}
        >
          Судьба зовёт.
        </h2>
        <p style={{ color: "var(--muted)", fontSize: 16, lineHeight: 1.6, marginBottom: 36 }}>
          Твой герой уже стоит на распутье у границ Скайрима. Позволь ему начать свой путь и напиши историю его славы.
        </p>

        <button
          onClick={() => onOpenAuth("register")}
          style={{
            padding: "16px 44px",
            fontSize: 15,
            fontFamily: "var(--font-mono)",
            fontWeight: 600,
            letterSpacing: "0.1em",
            textTransform: "uppercase",
            background: "var(--accent)",
            color: "var(--accent-on)",
            borderRadius: "var(--radius-sm)",
            border: "none",
            cursor: "pointer",
            boxShadow: "0 0 35px color-mix(in srgb, var(--accent) 45%, transparent)",
            transition: "all 0.2s ease",
          }}
          onMouseEnter={(e) => (e.currentTarget.style.transform = "scale(1.04)")}
          onMouseLeave={(e) => (e.currentTarget.style.transform = "scale(1)")}
        >
          Войти в мир Тамриэля
        </button>
      </section>

      {/* ─── Footer ────────────────────────────────────────────────────── */}
      <footer
        style={{
          marginTop: "auto",
          padding: "32px 24px",
          borderTop: "1px solid var(--border)",
          background: "var(--surface)",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 16,
          fontSize: 12,
          color: "var(--muted)",
          fontFamily: "var(--font-mono)",
        }}
      >
        <div style={{ display: "flex", gap: 24, textTransform: "uppercase", letterSpacing: "0.1em" }}>
          <span style={{ color: "var(--accent)" }}>The Elder Scrolls Idle</span>
          <span>·</span>
          <span>Вдохновлено Godville.net</span>
          <span>·</span>
          <span>Скайрим 4E 201</span>
        </div>
        <div style={{ opacity: 0.7 }}>
          Неофициальный фанатский проект. Все торговые марки The Elder Scrolls принадлежат Bethesda Softworks.
        </div>
      </footer>
    </div>
  )
}

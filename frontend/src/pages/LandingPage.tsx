import { useState } from "react"
import { ArrowRight, BookOpen, Compass, Moon, ScrollText, Shield, Sparkles, Sun } from "lucide-react"
import "./landing-observatory.css"

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
    <main className="landing-observatory">
      <header className="landing-observatory__header">
        <div className="landing-observatory__nav">
          <div className="landing-observatory__brand" aria-label="TES Idle — Врата Хроники">
            <span className="landing-observatory__seal"><ScrollText size={19} /></span>
            <span><strong>TES Idle</strong><small>Врата хроники</small></span>
          </div>
          <div className="landing-observatory__nav-actions">
            <button type="button" className="landing-observatory__icon-button" onClick={toggleTheme} aria-label={theme === "dark" ? "Включить светлую тему" : "Включить тёмную тему"} title={theme === "dark" ? "Светлая тема" : "Тёмная тема"}>
              {theme === "dark" ? <Sun size={17} /> : <Moon size={17} />}
            </button>
            <button type="button" className="landing-observatory__quiet-button" onClick={() => onOpenAuth("login")}>Войти</button>
            <button type="button" className="landing-observatory__primary-button landing-observatory__header-cta" onClick={() => onOpenAuth("register")}>Создать аккаунт</button>
          </div>
        </div>
      </header>

      <section className="landing-observatory__hero" aria-labelledby="landing-title">
        <div className="landing-observatory__orbital-map" aria-hidden="true"><span /><span /><span /></div>
        <div className="landing-observatory__hero-copy">
          <p className="landing-observatory__eyebrow"><Sparkles size={14} /> Личная обсерватория мира</p>
          <h1 id="landing-title">Врата<br /><em>Хроники</em></h1>
          <p className="landing-observatory__lead">Наблюдайте, как герой сам выбирает путь по Скайриму. Читайте его летопись, вмешивайтесь в судьбу и возвращайтесь к миру, который не замирает без вас.</p>
          <div className="landing-observatory__hero-actions">
            <button type="button" className="landing-observatory__primary-button" onClick={() => onOpenAuth("register")}>Начать хронику <ArrowRight size={17} /></button>
            <button type="button" className="landing-observatory__text-button" onClick={() => onOpenAuth("login")}>У меня уже есть аккаунт</button>
          </div>
        </div>
        <div className="landing-observatory__hero-index" aria-label="Что происходит в мире">
          <div><span>01</span><p><strong>Герой действует</strong>Сам выбирает нужды, цели и маршрут.</p></div>
          <div><span>02</span><p><strong>Хроника помнит</strong>События складываются в личную историю.</p></div>
          <div><span>03</span><p><strong>Вы направляете</strong>Поддерживаете героя в решающие моменты.</p></div>
        </div>
      </section>

      <section className="landing-observatory__manifesto" aria-labelledby="manifesto-title">
        <div className="landing-observatory__section-intro">
          <p className="landing-observatory__eyebrow">Что внутри</p>
          <h2 id="manifesto-title">Не игра в ожидание.<br />Наблюдение с последствиями.</h2>
          <p>Каждый раздел обсерватории показывает мир с новой стороны — без лишних экранов и обещаний.</p>
        </div>
        <div className="landing-observatory__cards">
          <article>
            <Compass size={22} aria-hidden="true" />
            <h3>Карта намерений</h3>
            <p>Герой оценивает угрозы, усталость и возможности, затем строит собственный путь по провинции.</p>
          </article>
          <article>
            <Shield size={22} aria-hidden="true" />
            <h3>Воля покровителя</h3>
            <p>Поддерживайте, лечите и вмешивайтесь тогда, когда вашей силы действительно ждут.</p>
          </article>
          <article>
            <BookOpen size={22} aria-hidden="true" />
            <h3>Живая хроника</h3>
            <p>Погода, память и характер героя остаются в записях — путь не повторяется дословно.</p>
          </article>
        </div>
      </section>

      <section className="landing-observatory__excerpt" aria-labelledby="excerpt-title">
        <div className="landing-observatory__excerpt-copy">
          <p className="landing-observatory__eyebrow">Фрагмент из архива</p>
          <h2 id="excerpt-title">Мир оставляет следы,<br />которые можно прочесть.</h2>
          <p>Хроника не пересказывает сухую статистику. Она собирает маршрут, встречи и последствия в последовательную историю героя.</p>
          <button type="button" className="landing-observatory__text-button" onClick={() => onOpenAuth("register")}>Открыть свою хронику <ArrowRight size={16} /></button>
        </div>
        <article className="landing-observatory__record">
          <div className="landing-observatory__record-head"><span>День 142 · Четвёртая Эпоха</span><small>ВЫСОКИЙ ХРОТГАР</small></div>
          <p>Ветры на Семи Тысячах Ступеней не отпускали путника. У святилища Кинарет он выбрал не сталь, а тихий обход — и нашёл амулет, оставленный задолго до его прихода.</p>
          <footer><span>Исследование</span><span>Находка</span><small>Запись сохранена</small></footer>
        </article>
      </section>

      <section className="landing-observatory__closing" aria-labelledby="closing-title">
        <p className="landing-observatory__eyebrow">Ваша точка наблюдения</p>
        <h2 id="closing-title">Откройте врата.<br /><em>Пусть история начнётся.</em></h2>
        <p>Создайте аккаунт — затем выберите героя и следите за его дорогой.</p>
        <button type="button" className="landing-observatory__primary-button" onClick={() => onOpenAuth("register")}>Создать аккаунт <ArrowRight size={17} /></button>
      </section>

      <footer className="landing-observatory__footer"><span>TES Idle · Врата хроники</span><span>Неофициальный фанатский проект по The Elder Scrolls</span></footer>
    </main>
  )
}

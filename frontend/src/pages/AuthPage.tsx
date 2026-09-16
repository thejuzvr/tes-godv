import { useState } from "react"
import { api } from "@/lib/api"
import { useGameStore } from "@/stores/gameStore"
import { ArrowLeft, Feather, KeyRound, Mail, ScrollText } from "lucide-react"
import "./auth-observatory.css"

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

  const changeMode = (nextMode: "login" | "register") => {
    setMode(nextMode)
    setError("")
  }

  const isRegistration = mode === "register"

  return (
    <main className="auth-observatory">
      <div className="auth-observatory__field" aria-hidden="true" />
      <section className="auth-observatory__frame" aria-labelledby="auth-title">
        <aside className="auth-observatory__folio">
          <div className="auth-observatory__brand">
            <span className="auth-observatory__seal"><ScrollText size={19} /></span>
            <span>
              <strong>TES Idle</strong>
              <small>Обсерватория хроники</small>
            </span>
          </div>
          <div className="auth-observatory__folio-copy">
            <p className="auth-observatory__eyebrow">Врата хроники</p>
            <h1 id="auth-title">{isRegistration ? "Откройте новую запись." : "Вернитесь к своей хронике."}</h1>
            <p>
              {isRegistration
                ? "Создайте учётную запись, чтобы наблюдать за судьбой героя и направлять её из обсерватории."
                : "Войдите, чтобы продолжить наблюдение за героем, миром и записями летописи."}
            </p>
          </div>
          <dl className="auth-observatory__ledger">
            <div><dt>Роль</dt><dd>Хранитель летописи</dd></div>
            <div><dt>Доступ</dt><dd>Личный архив</dd></div>
          </dl>
        </aside>

        <div className="auth-observatory__panel">
          {onBack && (
            <button type="button" className="auth-observatory__back" onClick={onBack}>
              <ArrowLeft size={15} /> К вратам хроники
            </button>
          )}

          <div className="auth-observatory__heading">
            <p className="auth-observatory__eyebrow">{isRegistration ? "Новая запись" : "Личный доступ"}</p>
            <h2>{isRegistration ? "Создать учётную запись" : "Войти"}</h2>
            <p>{isRegistration ? "Укажите данные для новой учётной записи." : "Введите данные, с которыми вы регистрировались."}</p>
          </div>

          <div className="auth-observatory__switch" role="group" aria-label="Выбор действия">
            <button type="button" aria-pressed={mode === "login"} onClick={() => changeMode("login")}>Войти</button>
            <button type="button" aria-pressed={isRegistration} onClick={() => changeMode("register")}>Создать аккаунт</button>
          </div>

          <form className="auth-observatory__form" onSubmit={handleSubmit}>
            <div className="auth-observatory__control">
              <label htmlFor="auth-username">Имя пользователя</label>
              <div className="auth-observatory__input-wrap">
                <Feather aria-hidden="true" size={17} />
                <input id="auth-username" name="username" type="text" placeholder="Например, Хранитель Севера" value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" spellCheck={false} required />
              </div>
            </div>

            {isRegistration && (
              <div className="auth-observatory__control">
                <label htmlFor="auth-email">Электронная почта</label>
                <div className="auth-observatory__input-wrap">
                  <Mail aria-hidden="true" size={17} />
                  <input id="auth-email" name="email" type="email" placeholder="name@example.com" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" spellCheck={false} required />
                </div>
              </div>
            )}

            <div className="auth-observatory__control">
              <label htmlFor="auth-password">Пароль</label>
              <div className="auth-observatory__input-wrap">
                <KeyRound aria-hidden="true" size={17} />
                <input id="auth-password" name="password" type="password" placeholder="Введите пароль" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete={isRegistration ? "new-password" : "current-password"} required />
              </div>
            </div>

            <div className="auth-observatory__status" aria-live="polite">
              {error && <p role="alert">{error}</p>}
            </div>

            <button className="auth-observatory__submit" type="submit" disabled={loading}>
              {loading ? "Проверка данных…" : isRegistration ? "Создать учётную запись" : "Продолжить в хронику"}
            </button>
          </form>
          <p className="auth-observatory__footnote">Доступ защищён личными данными вашей учётной записи.</p>
        </div>
      </section>
    </main>
  )
}

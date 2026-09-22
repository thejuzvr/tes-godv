import { useMemo } from "react"
import { Link } from "react-router-dom"

/**
 * TES-тематические страницы ошибок.
 *
 * 404 — «Донесение имперского курьера»: страница разыскивается, как беглый
 * преступник (плакат гильдии). 500 — экран смерти в духе духа DeathOverlay:
 * «Сервер пал в бою», с шуткой про возрождение.
 *
 * Тексты — задорные, но действие всегда конкретное: кнопки «Назад» и «На
 * панель героя» в обоих вариантах.
 */

const NOT_FOUND_FLAVOR = [
  "Эта дорога ведёт в Обливион. Мы туда не ходим — там скучно и без Wi-Fi.",
  "Стражник подозрительно щурится: «Кто-то украл твою страницу. И булочку с корицей».",
  "Стрела в колене — это больно. Страница 404 — это больнее.",
  "Картограф клялся, что карта была верной. Потом сжёг её именно на этом месте.",
  "Ни один путеводный камень не знает такой дороги. Даже тот, что врёт.",
  "Герой заглянул в этот угол Тамриэля и нашёл там только гоблина и тишину.",
]

const SERVER_ERROR_FLAVOR = [
  "Альдуин налетел на дата-центр. Кузнецы уже чинят броню серверов.",
  "Драугр-админ забыл завести реактор. Классика Скайрима.",
  "Что-то сгорело. Возможно, пресвитер. Возможно, запрос.",
  "Скайрим встретил Мехриуна Дагона. Дагон победил. Пока.",
  "Сервер пал в бою, как истинный норд. Сага о нём будет длинной.",
]

const BAD_REQUEST_FLAVOR = [
  "Твой Thu'um прозвучал как кашель. Голоса требуют проверить параметры запроса.",
  "Древние свитки такого формата не читают. Перепиши запрос по канону.",
]

const TOO_MANY_FLAVOR = [
  "Слишком часто стучишь в ворота. Стража вызывает дракона.",
  "Терпение стражников не безгранично, в отличие от очереди запросов.",
]

function pickOne(pool: string[]): string {
  return pool[Math.floor(Math.random() * pool.length)]
}

interface ErrorPageProps {
  code: string
  eyebrow: string
  headline: string
  sub: string
  flavor: string[]
  variant: "notice" | "death"
}

function ErrorPage({ code, eyebrow, headline, sub, flavor, variant }: ErrorPageProps) {
  const joke = useMemo(() => pickOne(flavor), [flavor])
  const goHome = () => { window.location.assign("/") }

  return (
    <div className={`err-shell err-${variant}`} role="alert">
      <div className="err-poster anim-fade-up">
        <div className="err-eyebrow">⚑ {eyebrow}</div>

        <div className="err-code" aria-hidden="true">{code}</div>

        <h1 className="err-headline">{headline}</h1>
        <p className="err-sub">{sub}</p>

        <div className="err-divider" aria-hidden="true">⚔ ⚔ ⚔</div>

        <blockquote className="err-joke">{joke}</blockquote>

        <div className="err-actions">
          <button type="button" className="err-btn err-btn-primary" onClick={() => window.history.back()}>
            ← Назад к безопасному пути
          </button>
          <Link to="/" className="err-btn">
            На панель героя
          </Link>
        </div>

        <div className="err-footnote">
          Имперский курьер не несёт ответственности за потерянные булочки с корицей.
        </div>
      </div>
    </div>
  )
}

/** 404 — маршрут вне карт Тамриэля. */
export function NotFoundPage() {
  return (
    <ErrorPage
      code="404"
      eyebrow="Донесение имперского курьера"
      headline="Разыскивается страница"
      sub="Эта дорога не значится ни на одной карте от Рифтена до Солитьюда."
      flavor={NOT_FOUND_FLAVOR}
      variant="notice"
    />
  )
}

/** 500 / крэш рендера — «экран смерти» с шуткой про возрождение. */
export function ServerErrorPage({ detail }: { detail?: string }) {
  return (
    <ErrorPage
      code="500"
      eyebrow="Хроника боевых потерь"
      headline="Сервер пал в бою"
      sub={detail || "Герои не умирают навсегда — и серверы тоже. Врата ожидания уже открыты."}
      flavor={SERVER_ERROR_FLAVOR}
      variant="death"
    />
  )
}

/** 400/429 и другие краткие радости — на будущее для инлайн-показа. */
export function BadRequestPage({ detail }: { detail?: string }) {
  return (
    <ErrorPage
      code="400"
      eyebrow="Драконий язык замолчал"
      headline="Голоса недовольны"
      sub={detail || "Запрос прозвучал невнятно. Скажи это иначе — и на колени, стрелок."}
      flavor={BAD_REQUEST_FLAVOR}
      variant="notice"
    />
  )
}

export function TooManyRequestsPage({ detail }: { detail?: string }) {
  return (
    <ErrorPage
      code="429"
      eyebrow="Приказ стражи"
      headline="Дождись рассвета"
      sub={detail || "Стража попросила больше так не стучать. Третье предупреждение."}
      flavor={TOO_MANY_FLAVOR}
      variant="notice"
    />
  )
}

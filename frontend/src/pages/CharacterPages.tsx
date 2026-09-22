import { useEffect, useState } from "react"
import { NavLink, Outlet } from "react-router-dom"
import { api, type HeroCard } from "@/lib/api"

const TRAITS: Record<string, string> = {
  bravery: "Храбрость", curiosity: "Любопытство", greed: "Жадность",
  sociability: "Общительность", tenacity: "Упорство", caution: "Осторожность",
  patience: "Терпение", dexterity: "Ловкость", empathy: "Эмпатия",
}

const SKILLS: Record<string, string> = {
  fishing: "Рыбалка", gathering: "Сбор", mining: "Руда", stealth: "Скрытность", lockpicking: "Взлом",
}

const BRANCH: Record<string, string> = {
  steel: "Сталь", trail: "Тропа", shadow: "Тень", name: "Имя", sign: "Знак",
}

export function CharacterLayout() {
  return (
    <section className="character-pages">
      <nav className="character-tabs" aria-label="Раздел персонажа">
        <NavLink to="/character" end>Паспорт</NavLink>
        <NavLink to="/character/skills">Навыки</NavLink>
        <NavLink to="/character/gear">Снаряжение</NavLink>
        <NavLink to="/analytics">Аналитика</NavLink>
      </nav>
      <Outlet />
    </section>
  )
}

export function PassportPage() {
  const [card, setCard] = useState<HeroCard | null>(null)
  const [text, setText] = useState("")
  const [notice, setNotice] = useState("")

  const load = () => api.getHeroCard().then((c) => { setCard(c); setText(c.hero.dossier || "") }).catch(() => setNotice("Карточка недоступна"))
  useEffect(() => { load() }, [])

  if (!card) return <p className="character-note">{notice || "Загрузка…"}</p>
  const hero = card.hero

  const save = async () => {
    setNotice("")
    try {
      const res = await api.updateDossier(text)
      setNotice(res.cost ? `Записано · −${res.cost} искра` : "Без изменений")
      load()
    } catch (e: any) {
      setNotice(e.message === "not_enough_sparks" ? "Не хватает искр" : "Не получилось записать")
    }
  }

  return (
    <div className="character-stack">
      <header className="character-head">
        <p>Паспорт</p>
        <h1>{hero.name}</h1>
        <span>{hero.race} · {hero.hero_class} · {hero.origin_label || "Предыстория не записана"}</span>
        <b>{hero.location?.name || "В пути"} · {hero.soul_sparks} искр</b>
        <small>Искры редки: победа над сильным врагом, завершённый квест, долгий онлайн-день и недельный лот лавки гильдии.</small>
      </header>

      <section className="character-block">
        <h2>Картотека</h2>
        <textarea value={text} maxLength={500} onChange={(e) => setText(e.target.value)} placeholder="Кто он для других. На решения героя не влияет." />
        <div>
          <button type="button" onClick={save}>Записать</button>
          <small>{text.trim() === (hero.dossier || "") ? "тот же текст бесплатно" : "правка стоит 1 искру"}</small>
          {notice && <em role="status">{notice}</em>}
        </div>
      </section>

      <section className="character-block">
        <h2>Нрав</h2>
        <ul className="character-traits">
          {Object.entries(TRAITS).map(([key, label]) => (
            <li key={key}><span>{label}</span><b>{Math.round(card.personality[key] ?? 50)}</b></li>
          ))}
        </ul>
      </section>
    </div>
  )
}

export function SkillsPage() {
  const [card, setCard] = useState<HeroCard | null>(null)
  const [notice, setNotice] = useState("")

  const load = () => api.getHeroCard().then(setCard).catch(() => setNotice("Навыки недоступны"))
  useEffect(() => { load() }, [])

  if (!card) return <p className="character-note">{notice || "Загрузка…"}</p>

  const buy = async (node: string) => {
    setNotice("")
    try {
      await api.buyPassive(node)
      setNotice("Узел усилен")
      load()
    } catch (e: any) {
      const reason: Record<string, string> = { not_enough_sparks: "Не хватает искр", locked: "Сначала предыдущий узел", max_rank: "Узел на пределе" }
      setNotice(reason[e.message] || "Не получилось купить")
    }
  }

  const branches = [...new Set(card.tree.map((n) => n.branch))]

  return (
    <div className="character-stack">
      <header className="character-head">
        <p>Навыки</p>
        <h1>Чем герой крепче</h1>
        <b>{card.hero.soul_sparks} искр</b>
        {notice && <em role="status">{notice}</em>}
      </header>

      <section className="character-block">
        <h2>Пассивы · за искры</h2>
        <div className="character-branches">
          {branches.map((branch) => (
            <div key={branch}>
              <h3>{BRANCH[branch] || branch}</h3>
              {card.tree.filter((n) => n.branch === branch).map((node) => {
                const rank = card.ranks[node.id] || 0
                const cost = card.costs[node.id]
                return (
                  <div key={node.id} className="character-node">
                    <span>{node.label}</span>
                    <b>{"●".repeat(rank)}{"○".repeat(3 - rank)}</b>
                    <button type="button" disabled={cost == null} onClick={() => buy(node.id)}>
                      {cost == null ? "—" : `${cost}✦`}
                    </button>
                  </div>
                )
              })}
            </div>
          ))}
        </div>
      </section>

      <section className="character-block">
        <h2>Ремесло · растёт от дел</h2>
        <ul className="character-traits">
          {Object.entries(SKILLS).map(([key, label]) => (
            <li key={key}><span>{label}</span><b>{Math.round(card.skills[key] || 0)}</b></li>
          ))}
        </ul>
      </section>
    </div>
  )
}

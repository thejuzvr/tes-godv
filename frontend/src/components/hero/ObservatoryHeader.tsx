import { ArrowUpRight, Compass, MapPin, Shield, Coins, Sun, Moon } from "lucide-react"
import { Link } from "react-router-dom"
import { StatBar } from "@/components/ui/StatBar"
import { formatNumber } from "@/lib/utils"
import type { Hero } from "@/stores/gameStore"

const STATES: Record<string, string> = {
  fighting: "Сражается", traveling: "В пути", resting: "Отдыхает", exploring: "Исследует мир",
  shopping: "Торгует", jailed: "В темнице", dead: "Ожидает возрождения", fishing: "Рыбачит",
  gathering: "Собирает травы", stealing: "Замышляет кражу", breaking_in: "Взламывает замок", pet_care: "Заботится о питомце",
}

export function ObservatoryHeader({ hero }: { hero: Hero & { generation?: number } }) {
  let bounty = 0
  try {
    const law = JSON.parse(hero.state_data || "{}").law
    bounty = Object.values<number>(law?.bounties || {}).reduce((sum, value) => sum + value, 0)
  } catch { /* Legacy state may be absent. */ }
  const day = hero.game_hour >= 6 && hero.game_hour < 18
  const hour = `${Math.floor(hero.game_hour).toString().padStart(2, "0")}:${Math.floor((hero.game_hour % 1) * 60).toString().padStart(2, "0")}`

  return (
    <header className="observatory-hero">
      <div className="observatory-landscape" aria-hidden="true">
        <svg viewBox="0 0 1000 320" preserveAspectRatio="xMidYMid slice">
          <defs>
            <linearGradient id="obs-mountain" x2="0" y2="1"><stop stopColor="currentColor" stopOpacity=".4"/><stop offset="1" stopColor="currentColor" stopOpacity=".05"/></linearGradient>
          </defs>
          <circle cx="770" cy="88" r="48" fill="none" stroke="currentColor" strokeOpacity=".3"/>
          <circle cx="770" cy="88" r="62" fill="none" stroke="currentColor" strokeOpacity=".12"/>
          <path d="M0 290 130 187 200 223 345 80 408 154 480 112 580 222 660 148 730 195 822 58 930 209 1000 157V320H0Z" fill="url(#obs-mountain)"/>
          <path d="m345 80-40 92 41-22 25 19 37-15M822 58l-43 103 45-25 30 30 29-8" fill="none" stroke="currentColor" strokeOpacity=".4"/>
          <path d="M0 320 180 260 290 283 440 207 555 270 655 234 770 288 923 213 1000 258V320Z" fill="currentColor" opacity=".12"/>
        </svg>
      </div>
      <div className="observatory-hero-top">
        <span className="observatory-eyebrow"><Compass size={15} aria-hidden="true"/> Скайрим · Личная хроника</span>
        <span className="observatory-date">{day ? <Sun size={15} aria-hidden="true"/> : <Moon size={15} aria-hidden="true"/>} День {hero.game_day} <span>·</span> {hour}</span>
      </div>
      <div className="observatory-identity">
        <div className="observatory-seal" aria-hidden="true">{hero.name.slice(0, 1)}</div>
        <div className="observatory-title">
          <div className="observatory-lineage">{hero.race} <span> / </span> {hero.hero_class} <span> / </span> Уровень {hero.level}</div>
          <h1>{hero.name}</h1>
          <div className="observatory-state"><span className={`observatory-beacon ${hero.state === "dead" || hero.state === "fighting" ? "is-danger" : ""}`} />{STATES[hero.state] || "Действует"}{(hero.generation || 1) > 1 && <span className="observatory-generation"> · Поколение {hero.generation}</span>}</div>
        </div>
        <div className="observatory-location">
          <span className="observatory-eyebrow"><MapPin size={14} aria-hidden="true"/> {hero.location?.region || "Скайрим"}</span>
          <Link to="/map" className="observatory-place">{hero.location?.name || "Неизвестная глушь"}<ArrowUpRight size={22} aria-hidden="true"/></Link>
          <span className="observatory-location-note">Опасность: {hero.location?.danger_level || "неизвестна"}{hero.location?.has_shop ? " · Лавка" : ""}{hero.location?.has_inn ? " · Таверна" : ""}</span>
        </div>
      </div>
      <div className="observatory-resources">
        <div className="observatory-vitals">
          <StatBar label="Здоровье" value={hero.hp} max={hero.max_hp} color="hp"/>
          <StatBar label="Магия" value={hero.mp} max={hero.max_mp} color="mp"/>
          <StatBar label="Выносливость" value={hero.sp} max={hero.max_sp} color="sp"/>
          <StatBar label="Опыт" value={hero.xp} max={hero.xp_to_next} color="xp"/>
        </div>
        <div className="observatory-purse"><Coins size={18} aria-hidden="true"/><strong>{formatNumber(hero.gold)}</strong><span>золота</span></div>
        <div className="observatory-purse"><strong>{hero.soul_sparks ?? 0}</strong><span>искр</span></div>
      </div>
      {bounty > 0 && <div className="observatory-bounty"><Shield size={15} aria-hidden="true"/> В розыске · награда {formatNumber(bounty)} золотых</div>}
    </header>
  )
}

import { useState, useEffect, useMemo } from "react"
import Markdown from "react-markdown"
import {
  Scroll,
  Sparkles,
  Feather,
  Check,
  Copy,
  Search,
  Library,
  Edit3,
  Save,
  X,
  Shield,
  HelpCircle,
  FileText,
  Bookmark,
  ListTree,
} from "lucide-react"
import { useGameStore } from "@/stores/gameStore"
import { api } from "@/lib/api"
import "./wiki-observatory.css"

/* ─── Wiki pages and categories ─────────────────────── */
interface WikiPageItem {
  id: string
  file: string
  icon: string
  title: string
  badge: string
  summary: string
}

interface WikiCategory {
  title: string
  icon: string
  pages: WikiPageItem[]
}

const WIKI_CATEGORIES: WikiCategory[] = [
  {
    title: "Основы и Мир",
    icon: "📜",
    pages: [
      {
        id: "overview",
        file: "overview.md",
        icon: "📖",
        title: "Обзор игры",
        badge: "База",
        summary: "Правила пути героя, автономный цикл и законы Тамриэля",
      },
      {
        id: "guild-news",
        file: "guild-news",
        icon: "📯",
        title: "Вести гильдий",
        badge: "Мир",
        summary: "Имперские депеши, закрытие Врат Обливиона и хроника знамён",
      },
    ],
  },
  {
    title: "Слово и Нарратив",
    icon: "🖋️",
    pages: [
      {
        id: "variables",
        file: "variables.md",
        icon: "🔤",
        title: "Переменные",
        badge: "Словник",
        summary: "Рунические маркеры, подставляемые процедурным движком в хронику",
      },
      {
        id: "narratives",
        file: "narratives.md",
        icon: "📝",
        title: "Нарративы",
        badge: "Каноны",
        summary: "Архитектура историй, композиция сцен и память героя",
      },
      {
        id: "types",
        file: "types.md",
        icon: "🏷️",
        title: "Типы шаблонов",
        badge: "События",
        summary: "Полный реестр типов ситуаций от битв до алтаря",
      },
      {
        id: "writing",
        file: "writing.md",
        icon: "✍️",
        title: "Гайд по написанию",
        badge: "Гайд",
        summary: "Справочник летописца по стилистике и тону хроники",
      },
    ],
  },
  {
    title: "Мастерская и Совет",
    icon: "🔮",
    pages: [
      {
        id: "ai-prompts",
        file: "ai-prompts.md",
        icon: "🤖",
        title: "AI-генерация",
        badge: "Промпты",
        summary: "Формулы для внешних моделей и импорта в ротацию",
      },
      {
        id: "suggestions",
        file: "suggestions.md",
        icon: "💡",
        title: "Доска предложений",
        badge: "Совет",
        summary: "Петиции архимагам и предложения новых шаблонов",
      },
    ],
  },
]

const ALL_WIKI_PAGES = WIKI_CATEGORIES.flatMap((c) => c.pages)

/* ─── AI Prompts panel (inline) ─────────────────────── */
const PROMPT_STYLES = [
  {
    id: "standard",
    label: "Стандартный",
    rune: "📜",
    description: "Нейтральное RPG-повествование летописца, строгое и выверенное",
  },
  {
    id: "atmospheric",
    label: "Атмосферный",
    rune: "🌙",
    description: "Поэтичный слог с акцентом на окружение, погоду, туманы и треск костра",
  },
  {
    id: "comic",
    label: "Комичный",
    rune: "🎭",
    description: "Ирония, мемы Скайрима, тавернные байки и ломание четвёртой стены",
  },
  {
    id: "dark",
    label: "Тёмное фэнтези",
    rune: "⚔️",
    description: "Мрачные хроники: кровь, стужа, отчаяние и несгибаемая воля к выживанию",
  },
]

const NARRATIVE_TYPES = [
  { id: "combat_start", label: "Бой: Начало", variables: "{monster_name}, {landmark}" },
  { id: "combat_result", label: "Бой: Победа", variables: "{hero_name}, {monster_name}, {rounds}, {xp}, {gold}" },
  { id: "combat_defeat", label: "Бой: Поражение", variables: "{hero_name}, {monster_name}" },
  { id: "equip", label: "Экипировка", variables: "{item_name}, {hero_name}" },
  { id: "explore", label: "Исследование", variables: "{terrain}, {discovery}, {landmark}" },
  { id: "rest", label: "Отдых", variables: "{hero_name}" },
  { id: "shop", label: "Покупки", variables: "{npc_name}, {item_name}, {gold_spent}" },
  { id: "social", label: "Общение", variables: "{npc_name}, {gamble_result}" },
  { id: "travel", label: "Путешествие", variables: "{hero_name}" },
  { id: "loot", label: "Добыча", variables: "{loot_text}" },
  { id: "death", label: "Смерть", variables: "{hero_name}" },
  { id: "god_encourage", label: "Бог: Вдохновить", variables: "{god_name}, {hero_name}" },
  { id: "god_punish", label: "Бог: Наказать", variables: "{god_name}, {hero_name}" },
  { id: "god_heal", label: "Бог: Исцелить", variables: "{god_name}, {hero_name}" },
  { id: "god_direct", label: "Бог: Направить", variables: "{god_name}, {hero_name}" },
  { id: "god_quest", label: "Бог: Задание", variables: "{god_name}, {hero_name}" },
  { id: "god_weather", label: "Бог: Погода", variables: "{god_name}, {hero_name}, {location_name}" },
  { id: "thought", label: "Мысли", variables: "{hero_name}" },
]

const PROMPT_TEMPLATES: Record<string, string> = {
  standard: `Ты — нарративный дизайнер для idle-игры в мире The Elder Scrolls (Скайрим).

Создай {count} шаблонов нарратива типа «{type}» на русском языке.

Требования:
- 2-3 предложения на каждый шаблон
- Стиль: нейтральное RPG-повествование, как в книге
- Используй переменные: {variable}
- Только русский язык, никакого китайского или английского
- Без эмодзи
- Без имён конкретных локаций — используй {location_name}

Верни ТОЛЬКО JSON массив объектов, без markdown:
[{"template_type": "{type_id}", "text_template": "шаблон 1"}, {"template_type": "{type_id}", "text_template": "шаблон 2"}]`,

  atmospheric: `Ты — поэт-повествователь для idle-игры в мире The Elder Scrolls (Скайрим).

Создай {count} атмосферных шаблонов нарратива типа «{type}» на русском языке.

Требования:
- 3-4 предложения на каждый шаблон
- Стиль: поэтичный, с акцентом на природу, погоду, освещение, звуки
- Создавай образы: туман, лунный свет, треск костра, запах хвои
- Используй переменные: {variable}
- Только русский язык
- Без эмодзи
- Без имён конкретных локаций — используй {location_name}

Верни ТОЛЬКО JSON массив объектов, без markdown:
[{"template_type": "{type_id}", "text_template": "шаблон 1"}, {"template_type": "{type_id}", "text_template": "шаблон 2"}]`,

  comic: `Ты — сценарист-сатирик для idle-игры в мире The Elder Scrolls (Скайрим).

Создай {count} комичных шаблонов нарратива типа «{type}» на русском языке.

Требования:
- 2-3 предложения на каждый шаблон
- Стиль: ирония, абсурд, мемы из TES-сообщества
- Герой может ломать четвёртую стену, жаловаться на игрока
- Ситуации: дракон в таверне, скелет в очереди, торговец-аферист
- Используй переменные: {variable}
- Только русский язык
- Без эмодзи
- Без имён конкретных локаций — используй {location_name}

Верни ТОЛЬКО JSON массив объектов, без markdown:
[{"template_type": "{type_id}", "text_template": "шаблон 1"}, {"template_type": "{type_id}", "text_template": "шаблон 2"}]`,

  dark: `Ты — автор тёмного фэнтези для idle-игры в мире The Elder Scrolls (Скайрим).

Создай {count} мрачных шаблонов нарратива типа «{type}» на русском языке.

Требования:
- 2-3 предложения на каждый шаблон
- Стиль: тёмное фэнтези, кровь, тьма, отчаяние, но без гротеска
- Герой страдает, но идёт вперёд
- В этом мире нет героев — только выжившие
- Используй переменные: {variable}
- Только русский язык
- Без эмодзи
- Без имён конкретных локаций — используй {location_name}

Верни ТОЛЬКО JSON массив объектов, без markdown:
[{"template_type": "{type_id}", "text_template": "шаблон 1"}, {"template_type": "{type_id}", "text_template": "шаблон 2"}]`,
}

function AIPromptsContent() {
  const [style, setStyle] = useState("standard")
  const [narrType, setNarrType] = useState("combat_start")
  const [count, setCount] = useState(5)
  const [copied, setCopied] = useState(false)

  const currentType = NARRATIVE_TYPES.find((t) => t.id === narrType) || NARRATIVE_TYPES[0]
  const currentStyleObj = PROMPT_STYLES.find((s) => s.id === style) || PROMPT_STYLES[0]

  const prompt = (PROMPT_TEMPLATES[style] || PROMPT_TEMPLATES.standard)
    .replace(/{count}/g, String(count))
    .replace(/{type}/g, currentType.label)
    .replace(/{type_id}/g, currentType.id)
    .replace(/{variable}/g, currentType.variables)

  const copyPrompt = () => {
    navigator.clipboard.writeText(prompt).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  return (
    <div className="space-y-6">
      {/* Introduction banner */}
      <div className="p-4 rounded-xl border border-accent/30 bg-gradient-to-r from-accent/15 via-surface to-surface-raised relative overflow-hidden">
        <div className="flex items-start gap-3">
          <div className="w-10 h-10 rounded-lg border border-accent/40 bg-accent/20 flex items-center justify-center text-accent shrink-0">
            <Sparkles className="w-5 h-5" />
          </div>
          <div>
            <h3 className="text-base font-bold text-accent font-display tracking-wide m-0">
              Кузница Нарративов · Мастерская Писаря
            </h3>
            <p className="text-xs text-muted mt-1 mb-0 leading-relaxed">
              Сформируйте безупречный свиток промпта для внешних языковых моделей (ChatGPT, Claude, Gemini). Сгенерированные JSON-шаблоны проверяются в Мастерской и обогащают живой мир Тамриэля.
            </p>
          </div>
        </div>
      </div>

      {/* Style selector cards */}
      <div>
        <label className="block text-[11px] font-mono uppercase tracking-wider text-muted mb-2.5">
          1. Тональность повествования
        </label>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          {PROMPT_STYLES.map((s) => {
            const active = style === s.id
            return (
              <button
                key={s.id}
                type="button"
                onClick={() => setStyle(s.id)}
                className={`text-left p-3.5 rounded-xl border transition-all cursor-pointer relative overflow-hidden flex flex-col justify-between ${
                  active
                    ? "border-accent bg-accent/20 shadow-[0_0_15px_-3px_rgba(201,162,39,0.35)] ring-1 ring-accent/60"
                    : "border-border/80 bg-surface/70 hover:bg-surface-raised hover:border-accent/40"
                }`}
              >
                <div>
                  <div className="flex items-center justify-between mb-1.5">
                    <span className="text-base">{s.rune}</span>
                    {active && <span className="text-[10px] font-mono text-accent uppercase font-bold tracking-wider">Выбрано</span>}
                  </div>
                  <div className={`text-sm font-bold font-display ${active ? "text-accent" : "text-fg"}`}>
                    {s.label}
                  </div>
                  <p className="text-[11px] text-muted leading-relaxed mt-1 mb-0">
                    {s.description}
                  </p>
                </div>
              </button>
            )
          })}
        </div>
      </div>

      {/* Type and count selectors */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 items-start">
        <div className="md:col-span-2">
          <label className="block text-[11px] font-mono uppercase tracking-wider text-muted mb-2.5">
            2. Тип события хроники
          </label>
          <div className="flex flex-wrap gap-1.5 max-h-48 overflow-y-auto p-2 rounded-xl border border-border/70 bg-surface/60">
            {NARRATIVE_TYPES.map((t) => {
              const active = narrType === t.id
              return (
                <button
                  key={t.id}
                  type="button"
                  onClick={() => setNarrType(t.id)}
                  title={`Переменные: ${t.variables}`}
                  className={`text-xs px-2.5 py-1 rounded-full border transition-all cursor-pointer ${
                    active
                      ? "border-accent bg-accent text-accent-on font-semibold shadow-sm"
                      : "border-border/80 bg-surface text-fg hover:border-accent/40 hover:bg-surface-raised"
                  }`}
                >
                  {t.label}
                </button>
              )
            })}
          </div>
        </div>

        <div>
          <label className="block text-[11px] font-mono uppercase tracking-wider text-muted mb-2.5">
            3. Объём свитка
          </label>
          <div className="p-3.5 rounded-xl border border-border/80 bg-surface/70 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs text-muted">Число шаблонов:</span>
              <select
                value={count}
                onChange={(e) => setCount(Number(e.target.value))}
                aria-label="Число шаблонов"
                className="px-3 py-1 rounded-lg border border-border bg-bg text-xs font-mono font-bold text-accent cursor-pointer focus:outline-none focus:border-accent"
              >
                {[3, 5, 10, 15, 20].map((n) => (
                  <option key={n} value={n}>
                    {n} вариантов
                  </option>
                ))}
              </select>
            </div>
            <div className="pt-2 border-t border-border/60 text-[11px] text-muted font-mono leading-tight">
              <span className="text-accent font-semibold">Переменные:</span> {currentType.variables}
            </div>
          </div>
        </div>
      </div>

      {/* Code preview & copy */}
      <div className="relative rounded-xl border border-accent/40 bg-black/50 shadow-inner overflow-hidden">
        <div className="flex items-center justify-between px-4 py-2.5 border-b border-border/60 bg-surface/80">
          <div className="flex items-center gap-2 text-xs font-mono text-muted">
            <Feather className="w-3.5 h-3.5 text-accent" />
            <span>Промпт для {currentStyleObj.label} ({currentType.label})</span>
          </div>
          <button
            type="button"
            onClick={copyPrompt}
            className={`px-3 py-1 rounded-lg text-xs font-mono font-medium flex items-center gap-1.5 transition-all cursor-pointer ${
              copied
                ? "bg-success text-white border border-success"
                : "bg-accent text-accent-on hover:brightness-110 border border-accent shadow-sm"
            }`}
          >
            {copied ? (
              <>
                <Check className="w-3.5 h-3.5" />
                <span>Запечатлено в буфер!</span>
              </>
            ) : (
              <>
                <Copy className="w-3.5 h-3.5" />
                <span>Скопировать свиток</span>
              </>
            )}
          </button>
        </div>
        <pre className="p-4 m-0 text-xs font-mono text-fg/90 whitespace-pre-wrap word-break leading-relaxed max-h-80 overflow-y-auto bg-transparent">
          {prompt}
        </pre>
      </div>

      {/* Step by step instructions */}
      <div className="p-4 rounded-xl border border-border/80 bg-surface/60 text-xs text-muted space-y-2">
        <div className="font-semibold text-fg flex items-center gap-1.5">
          <HelpCircle className="w-4 h-4 text-accent" />
          <span>Наставление писцу:</span>
        </div>
        <ol className="list-decimal pl-5 space-y-1 leading-relaxed text-[12px]">
          <li>Выберите желаемую тональность, тип хроники и количество вариантов выше.</li>
          <li>Скопируйте подготовленный промпт в буфер обмена.</li>
          <li>Передайте его языковой модели (ChatGPT, Claude, Gemini или локальной LLM).</li>
          <li>Полученный JSON массив сохраните и перейдите во вкладку <strong>«Мастерская нарративов → Импорт JSON»</strong>.</li>
          <li>После одобрения ваши строки войдут в живую историю Тамриэля!</li>
        </ol>
      </div>
    </div>
  )
}

/* ─── Guild News component ──────────────────────────── */
const GUILD_NEWS_META: Record<string, { label: string; icon: string; border: string; glow: string }> = {
  gate_closed: {
    label: "🌀 Врата Обливиона запечатаны",
    icon: "🌀",
    border: "border-l-purple-500",
    glow: "rgba(168, 85, 247, 0.2)",
  },
  guild_founded: {
    label: "⚔️ Основание гильдии",
    icon: "🛡️",
    border: "border-l-amber-500",
    glow: "rgba(245, 158, 11, 0.2)",
  },
  guild_levelup: {
    label: "👑 Новый ранг знамени",
    icon: "⭐",
    border: "border-l-sky-500",
    glow: "rgba(14, 165, 233, 0.2)",
  },
  guild_feast: {
    label: "🍺 Великий пир соратников",
    icon: "🍻",
    border: "border-l-emerald-500",
    glow: "rgba(16, 185, 129, 0.2)",
  },
}

function GuildNewsContent() {
  const [news, setNews] = useState<any[] | null>(null)

  useEffect(() => {
    api
      .getGuildNews()
      .then((res) => setNews(res.news ?? []))
      .catch(() => setNews([]))
  }, [])

  if (news === null) {
    return (
      <div className="py-12 text-center text-muted flex flex-col items-center gap-2">
        <Scroll className="w-8 h-8 text-accent animate-pulse" />
        <span className="font-display text-base">Имперские гонцы спешат с донесениями…</span>
      </div>
    )
  }

  if (news.length === 0) {
    return (
      <div className="p-8 rounded-xl border border-dashed border-border text-center text-muted">
        <Shield className="w-10 h-10 text-muted mx-auto mb-2 opacity-50" />
        <h4 className="font-display text-base text-fg mb-1">Пока тихо во владениях</h4>
        <p className="text-xs max-w-md mx-auto leading-relaxed">
          Ни одно знамя ещё не провозгласило свой триумф. Главы гильдий готовят рати на странице «Гильдия».
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-3.5">
      <div className="flex items-center justify-between pb-2 border-b border-border/60">
        <span className="text-xs font-mono uppercase tracking-wider text-muted">
          Хроника славных свершений ({news.length})
        </span>
        <span className="text-[11px] font-mono text-accent">Архивы Тамриэля</span>
      </div>

      {news.map((n) => {
        const meta = GUILD_NEWS_META[n.template_type] || {
          label: n.template_type,
          icon: "📜",
          border: "border-l-accent",
          glow: "rgba(201, 162, 39, 0.15)",
        }

        return (
          <div
            key={n.id}
            className={`p-4 rounded-xl border border-border/80 bg-surface/80 hover:bg-surface-raised transition-all border-l-4 ${meta.border}`}
            style={{ boxShadow: `0 4px 14px -3px ${meta.glow}` }}
          >
            <div className="flex items-center justify-between gap-2 mb-1.5">
              <span className="text-xs font-mono font-semibold text-fg flex items-center gap-1.5">
                <span>{meta.icon}</span>
                <span>{meta.label}</span>
              </span>
              <span className="text-[11px] font-mono text-muted">
                {new Date(n.created_at).toLocaleString("ru-RU", {
                  day: "numeric",
                  month: "long",
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </span>
            </div>
            <p className="text-sm leading-relaxed text-fg/90 m-0">
              {n.text}
            </p>
          </div>
        )
      })}
    </div>
  )
}

/* ─── Main Wiki Page Component ──────────────────────── */
export function WikiPage() {
  const isAdmin = useGameStore((s) => s.isAdmin)
  const [activePage, setActivePage] = useState("overview")
  const [searchQuery, setSearchQuery] = useState("")
  const [content, setContent] = useState("")
  const [loading, setLoading] = useState(true)
  const [editing, setEditing] = useState(false)
  const [editText, setEditText] = useState("")
  const [saving, setSaving] = useState(false)

  const currentPage = useMemo(
    () => ALL_WIKI_PAGES.find((p) => p.id === activePage) || ALL_WIKI_PAGES[0],
    [activePage],
  )
  const currentCategory = useMemo(
    () => WIKI_CATEGORIES.find((c) => c.pages.some((p) => p.id === activePage)),
    [activePage],
  )

  const isAiPrompts = activePage === "ai-prompts"
  const isGuildNews = activePage === "guild-news"

  // Filtered categories based on search
  const filteredCategories = useMemo(() => {
    const q = searchQuery.trim().toLowerCase()
    if (!q) return WIKI_CATEGORIES

    return WIKI_CATEGORIES.map((cat) => ({
      ...cat,
      pages: cat.pages.filter(
        (p) =>
          p.title.toLowerCase().includes(q) ||
          p.summary.toLowerCase().includes(q) ||
          p.badge.toLowerCase().includes(q),
      ),
    })).filter((cat) => cat.pages.length > 0)
  }, [searchQuery])

  // Extract headings for Table of Contents
  const tableOfContents = useMemo(() => {
    if (!content || isAiPrompts || isGuildNews || editing) return []
    const lines = content.split("\n")
    const items: { id: string; title: string; level: number }[] = []
    for (const line of lines) {
      const match = line.match(/^(#{2,3})\s+(.+)$/)
      if (match) {
        const level = match[1].length
        const title = match[2].replace(/[`*_]/g, "").trim()
        const id = title.toLowerCase().replace(/[^\w\u0400-\u04FF]+/g, "-")
        items.push({ id, title, level })
      }
    }
    return items
  }, [content, isAiPrompts, isGuildNews, editing])

  useEffect(() => {
    if (isAiPrompts || isGuildNews) {
      setLoading(false)
      return
    }
    setLoading(true)
    fetch(`/wiki/${currentPage.file}`)
      .then((r) => r.text())
      .then((raw) => {
        // Strip duplicate top-level # Title if present to avoid duplicate header in UI
        const cleaned = raw.replace(/^#\s+[^\n]+\n+/, "")
        setContent(cleaned)
      })
      .catch(() => setContent("Свиток утерян в архивах Драконьего Предела."))
      .finally(() => setLoading(false))
  }, [activePage, currentPage.file, isAiPrompts, isGuildNews])

  const startEdit = () => {
    setEditText(content)
    setEditing(true)
  }

  const savePage = async () => {
    setSaving(true)
    try {
      localStorage.setItem(`wiki_${currentPage.file}`, editText)
      setContent(editText)
      setEditing(false)
    } finally {
      setSaving(false)
    }
  }

  // Load local draft if exists
  useEffect(() => {
    if (!isAiPrompts && !isGuildNews) {
      const saved = localStorage.getItem(`wiki_${currentPage.file}`)
      if (saved) setContent(saved)
    }
  }, [activePage, currentPage.file, isAiPrompts, isGuildNews])

  return (
    <div className="wiki-observatory wiki-layout">
      {/* ── Left Sidebar (Ancient Codex Navigation) ── */}
      <nav className="wiki-sidebar" aria-label="Разделы Библиотеки">
        {/* Library Header Stamp */}
        <div className="wiki-sidebar-title">
          <Library className="w-4 h-4 text-accent" />
          <span>Архивы Библиотеки</span>
        </div>

        {/* Quick Search */}
        <div className="relative px-1 mb-1">
          <Search className="w-3.5 h-3.5 absolute left-3 top-2.5 text-muted pointer-events-none" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Поиск по свиткам…"
            aria-label="Поиск по свиткам"
            className="w-full pl-8 pr-3 py-1.5 rounded-lg border border-border/80 bg-surface text-xs text-fg placeholder:text-muted/60 focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent/40"
          />
          {searchQuery && (
            <button
              type="button"
              onClick={() => setSearchQuery("")}
              aria-label="Очистить поиск"
              className="absolute right-2.5 top-2 text-muted hover:text-fg text-xs p-0.5 cursor-pointer"
            >
              ×
            </button>
          )}
        </div>

        {/* Categories and page lists */}
        <div className="space-y-4">
          {filteredCategories.map((cat) => (
            <div key={cat.title}>
              <div className="wiki-sidebar-section-label flex items-center gap-1.5">
                <span>{cat.icon}</span>
                <span>{cat.title}</span>
              </div>
              <div className="space-y-0.5 mt-1">
                {cat.pages.map((p) => {
                  const active = activePage === p.id
                  return (
                    <button
                      key={p.id}
                      type="button"
                      className={active ? "active" : ""}
                      onClick={() => {
                        setActivePage(p.id)
                        setEditing(false)
                      }}
                    >
                      <span className="wiki-sidebar-icon">{p.icon}</span>
                      <div className="flex-1 min-w-0 pr-1">
                        <div className="flex items-center justify-between">
                          <span className="truncate">{p.title}</span>
                          <span
                            className={`text-[9px] font-mono px-1.5 py-0.2 rounded ${
                              active
                                ? "bg-accent text-accent-on font-bold"
                                : "bg-surface-raised text-muted"
                            }`}
                          >
                            {p.badge}
                          </span>
                        </div>
                      </div>
                    </button>
                  )
                })}
              </div>
            </div>
          ))}

          {filteredCategories.length === 0 && (
            <div className="text-center py-6 text-xs text-muted">
              Свитков по запросу не обнаружено
            </div>
          )}
        </div>

        {/* Footer info */}
        <div className="mt-auto pt-4 border-t border-border/60 text-[11px] text-muted font-mono leading-relaxed px-1">
          <span>Скайрим · Коллегия Винтерхолда</span>
          <div className="text-[10px] opacity-70">Летописи эпохи драконов</div>
        </div>
      </nav>

      {/* ── Main Manuscript Container with Wide Screen Table of Contents ── */}
      <main className="wiki-content">
        <div className="flex gap-6 w-full items-start">
          {/* Main Reading Column */}
          <div className="flex-1 min-w-0 space-y-6">
            {/* Article Banner Header */}
            <div className="wiki-manuscript-panel p-6 md:p-7 relative overflow-hidden">
              <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 relative z-10">
                <div className="space-y-1.5">
                  <div className="flex items-center gap-2 text-[11px] font-mono uppercase tracking-widest text-accent">
                    <Bookmark className="w-3.5 h-3.5" />
                    <span>{currentCategory?.title || "Имперская Библиотека"}</span>
                    <span>·</span>
                    <span className="text-muted">{currentPage.badge}</span>
                  </div>
                  <h1 className="wiki-title text-2xl md:text-3xl font-display font-bold text-fg m-0">
                    <span className="w-10 h-10 rounded-xl border border-accent/40 bg-accent/15 inline-flex items-center justify-center text-xl shrink-0">
                      {currentPage.icon}
                    </span>
                    <span>{currentPage.title}</span>
                  </h1>
                  <p className="text-sm text-muted leading-relaxed max-w-2xl m-0">
                    {currentPage.summary}
                  </p>
                </div>

                {/* Admin editor actions */}
                {isAdmin && !isAiPrompts && !isGuildNews && (
                  <div className="flex items-center gap-2 shrink-0">
                    {editing ? (
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={savePage}
                          disabled={saving}
                          className="px-3.5 py-1.5 rounded-lg text-xs font-medium bg-success text-white hover:brightness-110 flex items-center gap-1.5 shadow-sm cursor-pointer"
                        >
                          <Save className="w-3.5 h-3.5" />
                          <span>{saving ? "Запечатывание…" : "Запечатать"}</span>
                        </button>
                        <button
                          type="button"
                          onClick={() => setEditing(false)}
                          className="px-3 py-1.5 rounded-lg text-xs font-medium border border-border bg-surface text-fg hover:bg-surface-raised flex items-center gap-1 cursor-pointer"
                        >
                          <X className="w-3.5 h-3.5" />
                          <span>Отмена</span>
                        </button>
                      </div>
                    ) : (
                      <button
                        type="button"
                        onClick={startEdit}
                        className="px-3.5 py-1.5 rounded-lg text-xs font-medium border border-accent/40 bg-accent/10 text-accent hover:bg-accent/20 flex items-center gap-1.5 shadow-sm cursor-pointer transition-all"
                      >
                        <Edit3 className="w-3.5 h-3.5" />
                        <span>Править свиток</span>
                      </button>
                    )}
                  </div>
                )}
              </div>
            </div>

            {/* Article Body Content */}
            <div className="wiki-manuscript-panel min-h-[520px]">
              {isAiPrompts ? (
                <AIPromptsContent />
              ) : isGuildNews ? (
                <GuildNewsContent />
              ) : editing ? (
                <div className="space-y-4">
                  <div className="flex items-center justify-between text-xs text-muted">
                    <span className="font-mono text-warn">
                      ⚠ Правка свитка сохраняется в памяти вашего браузера.
                    </span>
                    <span className="font-mono text-accent">Формат: Markdown</span>
                  </div>
                  <textarea
                    value={editText}
                    onChange={(e) => setEditText(e.target.value)}
                    className="w-full min-h-[350px] p-4 rounded-xl border border-border bg-bg-elevated text-fg font-mono text-xs leading-relaxed focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent/50 resize-y"
                    placeholder="Начертайте текст свитка здесь…"
                  />
                  <div className="pt-4 border-t border-border/60">
                    <div className="text-xs font-mono uppercase tracking-wider text-muted mb-3 flex items-center gap-1.5">
                      <FileText className="w-3.5 h-3.5 text-accent" />
                      <span>Живой предпросмотр свитка</span>
                    </div>
                    <div className="wiki-markdown p-4 rounded-xl border border-border/50 bg-surface/40">
                      <Markdown>{editText}</Markdown>
                    </div>
                  </div>
                </div>
              ) : loading ? (
                <div className="py-20 text-center text-muted flex flex-col items-center justify-center gap-3">
                  <Scroll className="w-8 h-8 text-accent animate-pulse" />
                  <span className="font-display text-base">Свиток разворачивается пред вашим взором…</span>
                </div>
              ) : (
                <div className="wiki-markdown">
                  <Markdown
                    components={{
                      h2: ({ node: _, ...props }) => {
                        const text = String(props.children || "")
                        const id = text.toLowerCase().replace(/[^\w\u0400-\u04FF]+/g, "-")
                        return (
                          <h2 id={id} className="scroll-mt-6">
                            {props.children}
                          </h2>
                        )
                      },
                      h3: ({ node: _, ...props }) => {
                        const text = String(props.children || "")
                        const id = text.toLowerCase().replace(/[^\w\u0400-\u04FF]+/g, "-")
                        return (
                          <h3 id={id} className="scroll-mt-6">
                            {props.children}
                          </h3>
                        )
                      },
                    }}
                  >
                    {content}
                  </Markdown>
                </div>
              )}
            </div>
          </div>

          {/* Right Rail: Table of Contents / Scroll Outline (только очень широкие экраны:
              при xl контейнер 1440 — оглавление w-72 съедает треть манускрипта) */}
          {tableOfContents.length > 0 && (
            <aside className="w-64 hidden 2xl:block sticky top-6 shrink-0 space-y-4">
              <div className="wiki-manuscript-panel p-4">
                <div className="flex items-center gap-2 pb-2.5 mb-2 border-b border-border/60 text-xs font-mono uppercase tracking-wider text-accent font-semibold">
                  <ListTree className="w-3.5 h-3.5" />
                  <span>Оглавление свитка</span>
                </div>
                <nav className="space-y-1 max-h-[calc(100vh-220px)] overflow-y-auto pr-1">
                  {tableOfContents.map((item, idx) => (
                    <a
                      key={idx}
                      href={`#${item.id}`}
                      className={`block text-xs py-1.5 px-2.5 rounded-md transition-all text-muted hover:text-fg hover:bg-surface-raised truncate ${
                        item.level === 3 ? "pl-5 text-[11px]" : "font-medium"
                      }`}
                    >
                      <span className="mr-1.5 text-accent/70">•</span>
                      {item.title}
                    </a>
                  ))}
                </nav>
              </div>

              {/* Chronicle note */}
              <div className="p-4 rounded-xl border border-border/60 bg-surface text-xs text-muted leading-relaxed">
                <div className="text-accent font-semibold mb-1 flex items-center gap-1.5">
                  <Scroll className="w-3.5 h-3.5" />
                  <span>Архив Скайрима</span>
                </div>
                Навигация по разделам канона.
              </div>
            </aside>
          )}
        </div>
      </main>
    </div>
  )
}

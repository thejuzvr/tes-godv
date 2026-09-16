import { useState, useEffect, useCallback, useRef } from "react"
import { api } from "@/lib/api"
import { useGameStore } from "@/stores/gameStore"
import {
  TEMPLATE_TYPE_GROUPS, TEMPLATE_TYPES, VAR_GROUPS, EXAMPLE_JSON,
  previewTemplate, insertVariable,
} from "@/components/narrativeData"

// Мастерская нарративов (/narratives) — полноэкранная замена словника-модалки.
// Словник, создание шаблонов, предложения на модерацию (для авторов),
// база шаблонов и импорт JSON (для админа).

type Tab = "vars" | "create" | "suggest" | "browse" | "import"

const chipStyle = (highlight = false) => ({
  padding: "3px 8px",
  borderRadius: "var(--radius-sm)",
  border: `1px solid ${highlight ? "var(--accent)" : "var(--border)"}`,
  background: "var(--bg-elevated)",
  cursor: "pointer",
  fontSize: "var(--text-xs)",
  fontFamily: "var(--font-mono)",
  color: "var(--mp)",
  whiteSpace: "nowrap" as const,
})

function VarSidebar({ onInsert }: { onInsert: (v: string, ta: HTMLTextAreaElement | null) => void }) {
  const [copied, setCopied] = useState<string | null>(null)
  const copy = (v: string) => {
    navigator.clipboard?.writeText(v).then(() => {
      setCopied(v)
      setTimeout(() => setCopied(null), 1200)
    })
  }
  return (
    <aside style={{ position: "sticky", top: 12, maxHeight: "calc(100vh - 140px)", overflowY: "auto", minWidth: 0 }}>
      <div className="panel">
        <div className="panel-header" style={{ fontSize: "var(--text-sm)" }}>Словник переменных</div>
        <div className="panel-body">
          <p style={{ fontSize: "var(--text-xs)", color: "var(--muted)", marginTop: 0, lineHeight: 1.5 }}>
            Клик по чипу — вставить в текст. Клик по «⧉» — скопировать.
          </p>
          {VAR_GROUPS.map(g => (
            <div key={g.title} style={{ marginBottom: "var(--space-3)" }}>
              <div style={{ fontSize: 10, fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 4 }}>
                {g.title}
              </div>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>
                {g.vars.map(v => (
                  <span key={v.var} style={{ display: "inline-flex", alignItems: "center", gap: 2 }}>
                    <button onClick={() => onInsert(v.var, null)} title={`${v.label}${v.caseHint ? ` · ${v.caseHint}` : ""}: ${v.example}`} style={chipStyle()}>
                      {v.var}
                    </button>
                    <button onClick={() => copy(v.var)} title="Скопировать" aria-label={`Скопировать ${v.var}`}
                      style={{ ...chipStyle(), padding: "3px 5px", color: copied === v.var ? "var(--success)" : "var(--muted)", fontSize: 10 }}>
                      {copied === v.var ? "✓" : "⧉"}
                    </button>
                  </span>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </aside>
  )
}

function GlossaryTab() {
  const [copied, setCopied] = useState<string | null>(null)
  const [query, setQuery] = useState("")
  const copy = (v: string) => {
    navigator.clipboard?.writeText(v).then(() => {
      setCopied(v)
      setTimeout(() => setCopied(null), 1200)
    })
  }
  const q = query.trim().toLowerCase()
  const groups = q
    ? VAR_GROUPS.map(g => ({
        ...g,
        vars: g.vars.filter(v =>
          v.var.toLowerCase().includes(q) || v.label.toLowerCase().includes(q) ||
          (v.caseHint || "").toLowerCase().includes(q) || v.example.toLowerCase().includes(q)),
      })).filter(g => g.vars.length > 0)
    : VAR_GROUPS

  return (
    <div>
      <div className="panel" style={{ marginBottom: "var(--space-4)" }}>
        <div className="panel-header">Как это работает</div>
        <div className="panel-body" style={{ fontSize: "var(--text-sm)", lineHeight: 1.7, color: "var(--muted)" }}>
          <div style={{ color: "var(--fg)", marginBottom: "var(--space-1)" }}>
            Переменные в фигурных скобках движок подставляет при генерации нарратива.
          </div>
          <div>• У каждой переменной есть падеж или форма — соблюдайте её, иначе текст будет корявым («зашёл в Вайтран» вместо «зашёл в Вайтран»). Пример рядом с переменной показывает нужную форму.</div>
          <div>• Написали «{`{hero_name}`}» с опечаткой или несуществующее имя — переменная останется в тексте как есть. Это честный сигнал, что что-то не так.</div>
          <div>• Смотрите на контекст типа: «Смерть и возрождение» — переменные только для типа <code style={{ fontFamily: "var(--font-mono)", color: "var(--mp)" }}>death_respawn</code>, «Активности» — для рыбацких/воровских типов и т.д.</div>
        </div>
      </div>

      <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", marginBottom: "var(--space-3)" }}>
        <input
          value={query}
          onChange={e => setQuery(e.target.value)}
          placeholder="Поиск по переменным: имя, падеж, пример…"
          style={{ width: 320, padding: "7px 12px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)" }}
        />
        <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontFamily: "var(--font-mono)" }}>
          {groups.reduce((n, g) => n + g.vars.length, 0)} переменных
        </span>
      </div>

      {groups.map(g => (
        <div key={g.title} className="panel" style={{ marginBottom: "var(--space-3)" }}>
          <div className="panel-header">
            <span>{g.title}</span>
            <span style={{ color: "var(--muted)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)" }}>{g.hint}</span>
          </div>
          <div className="panel-body" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(300px, 1fr))", gap: "var(--space-2)" }}>
            {g.vars.map(v => (
              <button key={v.var} onClick={() => copy(v.var)}
                style={{ display: "flex", alignItems: "baseline", gap: "var(--space-2)", padding: "var(--space-2) var(--space-3)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", background: "var(--bg-elevated)", cursor: "pointer", textAlign: "left" }}
                title="Клик — скопировать переменную">
                <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: copied === v.var ? "var(--success)" : "var(--mp)", whiteSpace: "nowrap", fontWeight: 600 }}>
                  {copied === v.var ? "✓ скопировано" : v.var}
                </span>
                <span style={{ fontSize: "var(--text-xs)", color: "var(--fg)", flex: "0 1 auto", minWidth: 0 }}>
                  {v.label}
                  {v.caseHint && <span style={{ color: "var(--warn)", marginLeft: 4, fontSize: 10, fontFamily: "var(--font-mono)" }}>{v.caseHint}</span>}
                </span>
                <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)", fontStyle: "italic", marginLeft: "auto", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", maxWidth: 130 }} title={`Пример: ${v.example}`}>
                  {v.example}
                </span>
              </button>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}

function CreateTab() {
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const [type, setType] = useState("explore")
  const [text, setText] = useState("")
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<string | null>(null)

  const submit = async () => {
    if (!text.trim()) return
    setLoading(true)
    setResult(null)
    try {
      const res = await api.adminNarrativesImport([{
        template_type: type,
        text_template: text.trim(),
        source: "community",
      }])
      setResult(res.imported > 0 ? "Шаблон отправлен на модерацию" : `Ошибка: ${JSON.stringify(res)}`)
      if (res.imported > 0) setText("")
    } catch (e: any) {
      setResult(`Ошибка: ${e.message}`)
    }
    setLoading(false)
  }

  const insert = (v: string, ta: HTMLTextAreaElement | null) => {
    const target = ta ?? textareaRef.current
    if (target) insertVariable(target, v, setText)
  }

  const preview = previewTemplate(text || "Здесь появится превью…", [{ var: "{hero_name}", example: "Дракенфел" }, ...VAR_GROUPS.flatMap(g => g.vars)])

  return (
    <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) 380px", gap: "var(--space-4)", alignItems: "start" }}>
      <div>
        <div className="panel">
          <div className="panel-header">Новый шаблон</div>
          <div className="panel-body">
            <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Тип шаблона</label>
            <select value={type} onChange={e => setType(e.target.value)}
              style={{ padding: "7px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)", marginBottom: "var(--space-3)" }}>
              {TEMPLATE_TYPE_GROUPS.map(g => (
                <optgroup key={g.group} label={g.group}>
                  {g.types.map(t => <option key={t.id} value={t.id}>{t.label}</option>)}
                </optgroup>
              ))}
            </select>

            <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Текст шаблона</label>
            <textarea ref={textareaRef} value={text} onChange={e => setText(e.target.value)} rows={6}
              placeholder="Напишите нарратив. Вставляйте переменные чипами справа, например: Герой {hero_name} нашёл {discovery} у {landmark}."
              style={{ width: "100%", padding: "var(--space-2) var(--space-3)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)", resize: "vertical", lineHeight: 1.6, marginBottom: "var(--space-3)" }} />

            {text.trim() && (
              <div style={{ padding: "var(--space-2) var(--space-3)", background: "var(--bg-elevated)", borderRadius: "var(--radius-md)", borderLeft: "3px solid var(--accent)", marginBottom: "var(--space-3)" }}>
                <div style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", marginBottom: 4 }}>Превью (примеры вместо переменных)</div>
                <div style={{ fontSize: "var(--text-sm)", color: "var(--fg)", lineHeight: 1.5 }}>{preview}</div>
              </div>
            )}

            <button onClick={submit} disabled={loading || !text.trim()}
              style={{ padding: "8px 20px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: loading ? "wait" : "pointer", fontWeight: 600, opacity: loading || !text.trim() ? 0.5 : 1 }}>
              {loading ? "Отправка…" : "Отправить на модерацию"}
            </button>
            {result && (
              <div role="status" style={{ marginTop: "var(--space-3)", padding: "var(--space-2) var(--space-3)", background: result.startsWith("Ошибка") ? "color-mix(in oklab, var(--danger), transparent 90%)" : "color-mix(in oklab, var(--success), transparent 90%)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", color: result.startsWith("Ошибка") ? "var(--danger)" : "var(--success)" }}>
                {result}
              </div>
            )}
          </div>
        </div>
      </div>
      <VarSidebar onInsert={(v) => insert(v, null)} />
    </div>
  )
}

function SuggestTab() {
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const isAdmin = useGameStore((s) => s.isAdmin)
  const [type, setType] = useState("explore")
  const [text, setText] = useState("")
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<string | null>(null)
  const [mySuggestions, setMySuggestions] = useState<any[] | null>(null)

  useEffect(() => {
    if (mySuggestions === null) {
      api.getMySuggestions().then(setMySuggestions).catch(() => setMySuggestions([]))
    }
  }, [mySuggestions])

  const submit = async () => {
    if (!text.trim()) return
    setLoading(true)
    setResult(null)
    try {
      await api.createSuggestion("narrative", `Шаблон: ${TEMPLATE_TYPES.find(t => t.id === type)?.label || type}`, text.trim())
      setResult("Предложение отправлено — попадёт в модерацию админа.")
      setText("")
      api.getMySuggestions().then(setMySuggestions).catch(() => {})
    } catch (e: any) {
      setResult(`Ошибка: ${e.message}`)
    }
    setLoading(false)
  }

  const insert = (v: string) => {
    const ta = textareaRef.current
    if (ta) insertVariable(ta, v, setText)
    else setText(prev => prev + v)
  }

  return (
    <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) 380px", gap: "var(--space-4)", alignItems: "start" }}>
      <div>
        <div className="panel">
          <div className="panel-header">Предложить нарратив</div>
          <div className="panel-body">
            <p style={{ fontSize: "var(--text-xs)", color: "var(--muted)", marginTop: 0, lineHeight: 1.6 }}>
              Ваш текст попадёт на модерацию к админу и после одобрения появится в ротации игры.
              Пользуйтесь словником справа — переменные подставятся движком автоматически.
            </p>

            <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Тип шаблона</label>
            <select value={type} onChange={e => setType(e.target.value)}
              style={{ padding: "7px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)", marginBottom: "var(--space-3)" }}>
              {TEMPLATE_TYPE_GROUPS.map(g => (
                <optgroup key={g.group} label={g.group}>
                  {g.types.map(t => <option key={t.id} value={t.id}>{t.label}</option>)}
                </optgroup>
              ))}
            </select>

            <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Текст</label>
            <textarea ref={textareaRef} value={text} onChange={e => setText(e.target.value)} rows={6}
              placeholder="Например: Герой {hero_name} заметил {discovery} у старого тракта."
              style={{ width: "100%", padding: "var(--space-2) var(--space-3)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)", resize: "vertical", lineHeight: 1.6, marginBottom: "var(--space-3)" }} />

            <button onClick={submit} disabled={loading || !text.trim()}
              style={{ padding: "8px 20px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: loading ? "wait" : "pointer", fontWeight: 600, opacity: loading || !text.trim() ? 0.5 : 1 }}>
              {loading ? "Отправка…" : "Предложить"}
            </button>
            {result && (
              <div role="status" style={{ marginTop: "var(--space-3)", padding: "var(--space-2) var(--space-3)", background: result.startsWith("Ошибка") ? "color-mix(in oklab, var(--danger), transparent 90%)" : "color-mix(in oklab, var(--success), transparent 90%)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", color: result.startsWith("Ошибка") ? "var(--danger)" : "var(--success)" }}>
                {result}
              </div>
            )}
          </div>
        </div>

        {mySuggestions !== null && mySuggestions.length > 0 && (
          <div className="panel" style={{ marginTop: "var(--space-4)" }}>
            <div className="panel-header">Мои предложения <span style={{ color: "var(--muted)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)" }}>{mySuggestions.length}</span></div>
            <div className="panel-body" style={{ paddingTop: 0 }}>
              {mySuggestions.map((s) => (
                <div key={s.id} style={{ padding: "var(--space-2) 0", borderBottom: "1px solid var(--border)", display: "flex", alignItems: "center", gap: "var(--space-3)" }}>
                  <span style={{ padding: "2px 6px", borderRadius: "var(--radius-pill)", fontSize: 10, fontFamily: "var(--font-mono)", whiteSpace: "nowrap",
                    background: s.status === "approved" ? "color-mix(in oklab, var(--success), transparent 85%)" : s.status === "rejected" ? "color-mix(in oklab, var(--danger), transparent 85%)" : "color-mix(in oklab, var(--warn), transparent 85%)",
                    color: s.status === "approved" ? "var(--success)" : s.status === "rejected" ? "var(--danger)" : "var(--warn)" }}>
                    {s.status === "approved" ? "одобрено" : s.status === "rejected" ? "отклонено" : "на модерации"}
                  </span>
                  <span style={{ flex: 1, fontSize: "var(--text-sm)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{s.content}</span>
                </div>
              ))}
            </div>
          </div>
        )}
        {mySuggestions !== null && mySuggestions.length === 0 && !isAdmin && (
          <div style={{ marginTop: "var(--space-3)", fontSize: "var(--text-xs)", color: "var(--muted)" }}>
            Пока предложений нет — самое время написать первое.
          </div>
        )}
      </div>
      <VarSidebar onInsert={insert} />
    </div>
  )
}

function BrowseTab() {
  const [data, setData] = useState<any>(null)
  const [page, setPage] = useState(1)
  const [typeFilter, setTypeFilter] = useState("")

  const load = useCallback(async () => {
    try {
      const d = await api.adminNarrativeTemplates(page, 50, typeFilter || undefined)
      setData(d)
    } catch {}
  }, [page, typeFilter])

  useEffect(() => { load() }, [load])

  return (
    <div className="panel">
      <div className="panel-header">
        <span>Шаблоны в базе</span>
        {data && <span style={{ color: "var(--muted)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)" }}>{data.total} всего</span>}
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", padding: "var(--space-2) var(--space-3)", borderBottom: "1px solid var(--border)" }}>
        <select value={typeFilter} onChange={(e) => { setTypeFilter(e.target.value); setPage(1) }}
          style={{ padding: "4px 8px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", background: "var(--bg)", color: "var(--fg)", cursor: "pointer" }}>
          <option value="">Все типы</option>
          {TEMPLATE_TYPE_GROUPS.map(g => (
            <optgroup key={g.group} label={g.group}>
              {g.types.map(t => <option key={t.id} value={t.id}>{t.label}</option>)}
            </optgroup>
          ))}
        </select>
      </div>
      <div className="panel-body" style={{ maxHeight: "55vh", overflowY: "auto", paddingTop: 0 }}>
        {!data ? (
          <div style={{ color: "var(--muted)", padding: 16, textAlign: "center" }}>Загрузка…</div>
        ) : data.templates.length === 0 ? (
          <div style={{ color: "var(--muted)", padding: 16, textAlign: "center" }}>Нет шаблонов</div>
        ) : (
          data.templates.map((t: any) => (
            <div key={t.id} style={{ padding: "var(--space-2) 0", borderBottom: "1px solid var(--border)", display: "flex", alignItems: "center", gap: "var(--space-3)" }}>
              <span style={{ padding: "2px 6px", borderRadius: "var(--radius-pill)", fontSize: 10, fontFamily: "var(--font-mono)", background: t.is_active ? "color-mix(in oklab, var(--success), transparent 85%)" : "color-mix(in oklab, var(--warn), transparent 85%)", color: t.is_active ? "var(--success)" : "var(--warn)", whiteSpace: "nowrap" }}>
                {t.is_active ? "Активен" : "Ожидает"}
              </span>
              <span style={{ padding: "2px 6px", borderRadius: "var(--radius-pill)", fontSize: 10, fontFamily: "var(--font-mono)", background: "color-mix(in oklab, var(--fg), transparent 90%)", color: "var(--muted)", whiteSpace: "nowrap" }}>{t.source}</span>
              <span style={{ padding: "2px 6px", borderRadius: "var(--radius-pill)", fontSize: 10, fontFamily: "var(--font-mono)", background: "color-mix(in oklab, var(--mp), transparent 85%)", color: "var(--mp)", whiteSpace: "nowrap" }}>{t.template_type}</span>
              <span style={{ flex: 1, fontSize: "var(--text-sm)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{t.text_template}</span>
            </div>
          ))
        )}
        {data && data.total > 50 && (
          <div style={{ display: "flex", justifyContent: "center", gap: "var(--space-2)", padding: "var(--space-3)" }}>
            <button onClick={() => setPage(Math.max(1, page - 1))} disabled={page === 1} style={{ padding: "4px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--border)", background: page === 1 ? "transparent" : "var(--panel-bg)", cursor: page === 1 ? "default" : "pointer", fontSize: "var(--text-xs)" }}>Назад</button>
            <span style={{ fontFamily: "var(--font-mono)", fontSize: "var(--text-xs)", color: "var(--muted)" }}>{page}</span>
            <button onClick={() => setPage(page + 1)} disabled={data.templates.length < 50} style={{ padding: "4px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--border)", background: data.templates.length < 50 ? "transparent" : "var(--panel-bg)", cursor: data.templates.length < 50 ? "default" : "pointer", fontSize: "var(--text-xs)" }}>Вперёд</button>
          </div>
        )}
      </div>
    </div>
  )
}

function ImportTab() {
  const importTextareaRef = useRef<HTMLTextAreaElement>(null)
  const [jsonText, setJsonText] = useState("")
  const [defaultType, setDefaultType] = useState("explore")
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<any>(null)
  const [error, setError] = useState("")

  const applyExample = (example: object[]) => {
    const current = jsonText.trim()
    if (!current) { setJsonText(JSON.stringify(example, null, 2)); return }
    try {
      const parsed = JSON.parse(current)
      if (Array.isArray(parsed)) { setJsonText(JSON.stringify([...parsed, ...example], null, 2)); return }
    } catch { /* fall through to replace */ }
    setJsonText(JSON.stringify(example, null, 2))
  }

  const handleImport = async () => {
    setError("")
    setResult(null)
    let parsed: any[]
    try {
      parsed = JSON.parse(jsonText)
      if (!Array.isArray(parsed)) throw new Error("Ожидается JSON массив")
    } catch (e: any) {
      setError(`Ошибка JSON: ${e.message}`)
      return
    }
    const templates = parsed.map(t => ({
      template_type: t.template_type || defaultType,
      text_template: t.text_template || t.text || "",
      source: t.source || "community",
    }))
    setLoading(true)
    try {
      const res = await api.adminNarrativesImport(templates)
      setResult(res)
      if (res.imported > 0) setJsonText("")
    } catch (e: any) {
      setError(e.message || "Ошибка импорта")
    }
    setLoading(false)
  }

  return (
    <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) 380px", gap: "var(--space-4)", alignItems: "start" }}>
      <div className="panel">
        <div className="panel-header">Импорт JSON</div>
        <div className="panel-body">
          <p style={{ fontSize: "var(--text-xs)", color: "var(--muted)", marginTop: 0 }}>
            Массив шаблонов: <code>{'{"template_type": "...", "text_template": "..."}'}</code>. Шаблоны идут в модерацию.
          </p>

          <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 6 }}>
            Примеры (клик — заполнит поле, повторный — добавит к существующему)
          </label>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(190px, 1fr))", gap: "var(--space-2)", marginBottom: "var(--space-3)" }}>
            {EXAMPLE_JSON.map(ex => (
              <button key={ex.title} onClick={() => applyExample(ex.json)}
                style={{ textAlign: "left", padding: "var(--space-2) var(--space-3)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", background: "var(--bg-elevated)", cursor: "pointer" }}>
                <div style={{ fontSize: "var(--text-sm)", fontWeight: 600, color: "var(--fg)", marginBottom: 2 }}>{ex.title}</div>
                <div style={{ fontSize: "var(--text-xs)", color: "var(--muted)", lineHeight: 1.4 }}>{ex.desc}</div>
              </button>
            ))}
          </div>

          <label style={{ fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", color: "var(--muted)", textTransform: "uppercase", display: "block", marginBottom: 4 }}>Тип по умолчанию (если не указан в JSON)</label>
          <select value={defaultType} onChange={e => setDefaultType(e.target.value)}
            style={{ padding: "6px 10px", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", background: "var(--bg)", color: "var(--fg)", marginBottom: "var(--space-3)" }}>
            {TEMPLATE_TYPE_GROUPS.map(g => (
              <optgroup key={g.group} label={g.group}>
                {g.types.map(t => <option key={t.id} value={t.id}>{t.label}</option>)}
              </optgroup>
            ))}
          </select>

          <textarea ref={importTextareaRef} value={jsonText} onChange={e => setJsonText(e.target.value)} rows={10}
            placeholder='[{"template_type": "explore", "text_template": "Герой нашёл {discovery}."}]'
            style={{ width: "100%", padding: "var(--space-2) var(--space-3)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)", fontFamily: "var(--font-mono)", background: "var(--bg)", color: "var(--fg)", resize: "vertical", lineHeight: 1.5 }} />

          <div style={{ marginTop: "var(--space-3)" }}>
            <button onClick={handleImport} disabled={loading || !jsonText.trim()}
              style={{ padding: "8px 20px", background: "var(--accent)", color: "var(--accent-on)", borderRadius: "var(--radius-md)", fontSize: "var(--text-sm)", border: "none", cursor: loading ? "wait" : "pointer", fontWeight: 600, opacity: loading || !jsonText.trim() ? 0.5 : 1 }}>
              {loading ? "Импорт…" : "Отправить на модерацию"}
            </button>
          </div>
          {error && <div role="status" style={{ marginTop: "var(--space-3)", padding: "var(--space-2) var(--space-3)", background: "color-mix(in oklab, var(--danger), transparent 90%)", borderRadius: "var(--radius-md)", color: "var(--danger)", fontSize: "var(--text-xs)" }}>{error}</div>}
          {result && <div role="status" style={{ marginTop: "var(--space-3)", padding: "var(--space-2) var(--space-3)", background: "color-mix(in oklab, var(--success), transparent 90%)", borderRadius: "var(--radius-md)", fontSize: "var(--text-xs)" }}>Импортировано: {result.imported}</div>}
        </div>
      </div>
      <VarSidebar onInsert={(v) => { const ta = importTextareaRef.current; if (ta) insertVariable(ta, v, setJsonText) }} />
    </div>
  )
}

export function NarrativesPage() {
  const isAdmin = useGameStore((s) => s.isAdmin)
  const [tab, setTab] = useState<Tab>("vars")

  const tabBtn = (id: Tab, label: string) => (
    <button onClick={() => setTab(id)}
      style={{
        padding: "7px 16px",
        borderRadius: "var(--radius-pill)",
        border: `1px solid ${tab === id ? "var(--accent)" : "var(--border)"}`,
        cursor: "pointer",
        background: tab === id ? "var(--accent)" : "var(--bg)",
        color: tab === id ? "var(--accent-on)" : "var(--fg)",
        fontSize: "var(--text-sm)",
        fontWeight: tab === id ? 600 : 400,
        transition: "background 150ms, color 150ms",
      }}>
      {label}
    </button>
  )

  return (
    <div style={{ padding: "var(--space-4) 0" }}>
      <div style={{ display: "flex", alignItems: "baseline", gap: "var(--space-3)", marginBottom: "var(--space-2)" }}>
        <h1 style={{ margin: 0, fontSize: "var(--text-xl)", fontWeight: 700 }}>🖋️ Мастерская нарративов</h1>
        <span style={{ fontSize: "var(--text-xs)", color: "var(--muted)" }}>
          словник переменных, создание и предложение шаблонов — одобренные тексты попадают в ротацию игры
        </span>
      </div>

      <div style={{ display: "flex", gap: "var(--space-2)", flexWrap: "wrap", marginBottom: "var(--space-4)" }}>
        {tabBtn("vars", "📖 Словник")}
        {tabBtn("create", "✍️ Создать шаблон")}
        {tabBtn("suggest", "📨 Предложить")}
        {isAdmin && tabBtn("browse", "🗄️ Шаблоны в базе")}
        {isAdmin && tabBtn("import", "📥 Импорт JSON")}
      </div>

      {tab === "vars" && <GlossaryTab />}
      {tab === "create" && <CreateTab />}
      {tab === "suggest" && <SuggestTab />}
      {tab === "browse" && isAdmin && <BrowseTab />}
      {tab === "import" && isAdmin && <ImportTab />}
    </div>
  )
}

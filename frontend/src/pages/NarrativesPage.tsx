import { useState, useEffect, useCallback, useRef } from "react"
import { api } from "@/lib/api"
import { useGameStore } from "@/stores/gameStore"
import {
  TEMPLATE_TYPE_GROUPS, TEMPLATE_TYPES, VAR_GROUPS, EXAMPLE_JSON,
  previewTemplate, insertVariable,
} from "@/components/narrativeData"
import "./narratives-observatory.css"

type Tab = "vars" | "create" | "suggest" | "browse" | "import"
type Notice = { kind: "success" | "error"; text: string } | null

const STATUS_COPY: Record<string, { label: string; detail: string; tone: string }> = {
  approved: { label: "Одобрено", detail: "Шаблон уже может попасть в игровую ротацию.", tone: "success" },
  rejected: { label: "Нужна доработка", detail: "Посмотрите комментарий редактора и попробуйте снова.", tone: "danger" },
  pending: { label: "На рассмотрении", detail: "Редактор проверит тип, переменные и тон текста.", tone: "warning" },
}

function TypeSelect({ value, onChange, id, includeAll = false }: { value: string; onChange: (value: string) => void; id: string; includeAll?: boolean }) {
  return <select id={id} value={value} onChange={e => onChange(e.target.value)}>
    {includeAll && <option value="">Все типы</option>}
    {TEMPLATE_TYPE_GROUPS.map(group => <optgroup key={group.group} label={group.group}>
      {group.types.map(type => <option key={type.id} value={type.id}>{type.label}</option>)}
    </optgroup>)}
  </select>
}

function VariableRail({ onInsert }: { onInsert: (value: string) => void }) {
  const [copied, setCopied] = useState<string | null>(null)
  const copy = async (value: string) => {
    try {
      await navigator.clipboard?.writeText(value)
      setCopied(value)
      window.setTimeout(() => setCopied(null), 1400)
    } catch { /* insertion remains available when clipboard permission is denied */ }
  }

  return <aside className="narrative-variable-rail" aria-label="Инструменты словника">
    <div className="narrative-rail-heading">
      <span className="narrative-kicker">Палитра слов</span>
      <h2>Переменные движка</h2>
      <p>Вставляйте чип в точку курсора. Копия пригодится для заметок.</p>
    </div>
    <div className="narrative-variable-groups">
      {VAR_GROUPS.map(group => <section key={group.title} className="narrative-variable-group" aria-label={group.title}>
        <div className="narrative-variable-group-title"><strong>{group.title}</strong><span>{group.hint}</span></div>
        <div className="narrative-chip-list">
          {group.vars.map(variable => <div className="narrative-variable-chip" key={variable.var}>
            <button type="button" onClick={() => onInsert(variable.var)} title={`${variable.label}${variable.caseHint ? ` · ${variable.caseHint}` : ""}. Пример: ${variable.example}`}>
              <code>{variable.var}</code>
            </button>
            <button type="button" className="narrative-copy" onClick={() => copy(variable.var)} aria-label={`Скопировать ${variable.var}`} title="Скопировать переменную">
              {copied === variable.var ? "✓" : "⧉"}
            </button>
          </div>)}
        </div>
      </section>)}
    </div>
  </aside>
}

function NoticeBox({ notice }: { notice: Notice }) {
  if (!notice) return null
  return <div className={`narrative-notice ${notice.kind}`} role={notice.kind === "error" ? "alert" : "status"} aria-live="polite">{notice.text}</div>
}

function GlossaryTab() {
  const [query, setQuery] = useState("")
  const [copied, setCopied] = useState<string | null>(null)
  const q = query.trim().toLowerCase()
  const groups = q ? VAR_GROUPS.map(group => ({ ...group, vars: group.vars.filter(variable =>
    variable.var.toLowerCase().includes(q) || variable.label.toLowerCase().includes(q) ||
    (variable.caseHint || "").toLowerCase().includes(q) || variable.example.toLowerCase().includes(q),
  ) })).filter(group => group.vars.length) : VAR_GROUPS
  const count = groups.reduce((total, group) => total + group.vars.length, 0)
  const copy = async (value: string) => {
    try { await navigator.clipboard?.writeText(value); setCopied(value); window.setTimeout(() => setCopied(null), 1400) } catch { /* no-op */ }
  }

  return <div className="narrative-glossary">
    <section className="narrative-guidance" aria-labelledby="glossary-guide-title">
      <div><span className="narrative-kicker">Как читать хронику</span><h2 id="glossary-guide-title">Слово в скобках — место для живого мира</h2></div>
      <div className="narrative-guidance-steps">
        <p><b>1. Выберите тип.</b> Он определяет, какие события и переменные встретятся.</p>
        <p><b>2. Проверьте форму.</b> Подсказка падежа рядом с переменной важнее красивой фразы.</p>
        <p><b>3. Копируйте точно.</b> Неизвестная переменная останется в тексте — это сигнал ошибки.</p>
      </div>
    </section>
    <div className="narrative-search-row">
      <label htmlFor="narrative-variable-search">Найти переменную</label>
      <input id="narrative-variable-search" value={query} onChange={e => setQuery(e.target.value)} placeholder="Имя, падеж или пример…" />
      <output aria-live="polite">{count} {count === 1 ? "переменная" : "переменных"}</output>
    </div>
    {groups.length ? groups.map(group => <section className="narrative-glossary-group" key={group.title}>
      <header><h2>{group.title}</h2><span>{group.hint}</span></header>
      <div className="narrative-glossary-grid">
        {group.vars.map(variable => <button type="button" key={variable.var} onClick={() => copy(variable.var)} className="narrative-glossary-card" title="Скопировать переменную">
          <code>{copied === variable.var ? "✓ скопировано" : variable.var}</code>
          <span><b>{variable.label}</b>{variable.caseHint && <em>{variable.caseHint}</em>}</span>
          <small>{variable.example}</small>
        </button>)}
      </div>
    </section>) : <div className="narrative-empty">По этому запросу переменных нет. Попробуйте название, падеж или пример.</div>}
  </div>
}

function TemplateEditor({ mode }: { mode: "create" | "suggest" }) {
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const [type, setType] = useState("explore")
  const [text, setText] = useState("")
  const [loading, setLoading] = useState(false)
  const [notice, setNotice] = useState<Notice>(null)
  const [mySuggestions, setMySuggestions] = useState<any[] | null>(mode === "suggest" ? null : [])
  const isSuggestion = mode === "suggest"
  const typeLabel = TEMPLATE_TYPES.find(item => item.id === type)?.label || type
  const preview = previewTemplate(text || "Здесь появится ваш текст — с примерами вместо переменных.", [{ var: "{hero_name}", example: "Дракенфел" }, ...VAR_GROUPS.flatMap(group => group.vars)])

  const refreshSuggestions = useCallback(() => {
    if (isSuggestion) api.getMySuggestions().then(setMySuggestions).catch(() => setMySuggestions([]))
  }, [isSuggestion])
  useEffect(() => { refreshSuggestions() }, [refreshSuggestions])

  const insert = (value: string) => {
    if (textareaRef.current) insertVariable(textareaRef.current, value, setText)
    else setText(previous => previous + value)
  }
  const submit = async () => {
    if (!text.trim()) { setNotice({ kind: "error", text: "Напишите текст шаблона перед отправкой." }); textareaRef.current?.focus(); return }
    setLoading(true); setNotice(null)
    try {
      if (isSuggestion) {
        await api.createSuggestion("narrative", `Шаблон: ${typeLabel}`, text.trim())
        setNotice({ kind: "success", text: "Предложение принято. Оно ждёт проверки редактором в разделе модерации." })
        refreshSuggestions()
      } else {
        const result = await api.adminNarrativesImport([{ template_type: type, text_template: text.trim(), source: "community" }])
        if (!result.imported) throw new Error("Сервер не добавил шаблон. Проверьте текст и повторите попытку.")
        setNotice({ kind: "success", text: "Шаблон отправлен на модерацию. После одобрения он появится в ротации." })
      }
      setText("")
    } catch (error: any) { setNotice({ kind: "error", text: `Не удалось отправить: ${error.message || "неизвестная ошибка"}` }) }
    finally { setLoading(false) }
  }

  return <div className="narrative-workbench">
    <div className="narrative-editor-column">
      <section className="narrative-editor-card" aria-labelledby={`${mode}-form-title`}>
        <header>
          <span className="narrative-kicker">{isSuggestion ? "Письмо в редакцию" : "Редакторская запись"}</span>
          <h2 id={`${mode}-form-title`}>{isSuggestion ? "Предложите строку для летописи" : "Создайте новый шаблон"}</h2>
          <p>{isSuggestion ? "Текст сначала проходит модерацию: редактор проверяет событие, переменные и читаемость. Одобренный вариант становится частью живой хроники." : "Добавьте шаблон в очередь модерации. Используйте палитру переменных, чтобы текст получил данные события."}</p>
        </header>
        <div className="narrative-form-grid">
          <div><label htmlFor={`${mode}-type`}>Событие</label><TypeSelect id={`${mode}-type`} value={type} onChange={setType} /></div>
          <div className="narrative-selected-type"><span>Вы выбрали</span><strong>{typeLabel}</strong></div>
        </div>
        <label htmlFor={`${mode}-text`}>Текст шаблона</label>
        <textarea ref={textareaRef} id={`${mode}-text`} value={text} onChange={e => setText(e.target.value)} rows={7}
          aria-describedby={`${mode}-help ${mode}-preview`} placeholder="Например: Герой {hero_name} заметил {discovery} у старого тракта." />
        <p id={`${mode}-help`} className="narrative-field-help">Переменные вставляются в фигурных скобках. Выбирайте только те, что подходят событию.</p>
        <div className="narrative-preview" id={`${mode}-preview`} aria-live="polite"><span>Пробный оттиск</span><p>{preview}</p></div>
        <div className="narrative-submit-row"><button type="button" className="narrative-primary" onClick={submit} disabled={loading || !text.trim()}>{loading ? "Отправляем…" : isSuggestion ? "Отправить редактору" : "Передать на модерацию"}</button><span>{isSuggestion ? "Вы сможете следить за статусом ниже." : "Шаблон не станет активным без проверки."}</span></div>
        <NoticeBox notice={notice} />
      </section>
      {isSuggestion && <SuggestionLedger suggestions={mySuggestions} />}
    </div>
    <VariableRail onInsert={insert} />
  </div>
}

function SuggestionLedger({ suggestions }: { suggestions: any[] | null }) {
  const readableFeedback = (suggestion: any) => suggestion.admin_comment || suggestion.comment
  return <section className="narrative-ledger" aria-labelledby="suggestion-ledger-title">
    <header><div><span className="narrative-kicker">Мой архив</span><h2 id="suggestion-ledger-title">Статусы предложений</h2></div>{suggestions && <span className="narrative-count">{suggestions.length}</span>}</header>
    {suggestions === null ? <p className="narrative-loading">Загружаем ваш архив…</p> : suggestions.length === 0 ? <div className="narrative-empty"><b>Архив пока пуст.</b><br />Первое предложение появится здесь вместе с его статусом.</div> : <ul>
      {suggestions.map(suggestion => {
        const status = STATUS_COPY[suggestion.status] || STATUS_COPY.pending
        return <li key={suggestion.id}>
          <div className="narrative-suggestion-meta"><span className={`narrative-status ${status.tone}`}>{status.label}</span><span>{status.detail}</span></div>
          <p>{suggestion.content}</p>
          {readableFeedback(suggestion) && <div className="narrative-editor-feedback"><b>Комментарий редактора</b><span>{readableFeedback(suggestion)}</span></div>}
        </li>
      })}
    </ul>}
  </section>
}

function BrowseTab() {
  const [data, setData] = useState<any>(null)
  const [page, setPage] = useState(1)
  const [typeFilter, setTypeFilter] = useState("")
  const [error, setError] = useState("")
  const load = useCallback(async () => {
    try { setError(""); setData(await api.adminNarrativeTemplates(page, 50, typeFilter || undefined)) }
    catch (e: any) { setError(`Не удалось загрузить шаблоны: ${e.message || "неизвестная ошибка"}`) }
  }, [page, typeFilter])
  useEffect(() => { load() }, [load])
  const pages = data ? Math.max(1, Math.ceil(data.total / 50)) : 1

  return <section className="narrative-database" aria-labelledby="database-title">
    <header><div><span className="narrative-kicker">Редакторский фонд</span><h2 id="database-title">Шаблоны в базе</h2></div>{data && <span className="narrative-count">{data.total} всего</span>}</header>
    <div className="narrative-database-tools"><label htmlFor="template-filter">Событие</label><TypeSelect id="template-filter" value={typeFilter} includeAll onChange={value => { setTypeFilter(value); setPage(1) }} /></div>
    {error ? <NoticeBox notice={{ kind: "error", text: error }} /> : !data ? <p className="narrative-loading">Открываем хранилище…</p> : data.templates.length === 0 ? <div className="narrative-empty">В этом разделе пока нет шаблонов.</div> : <div className="narrative-template-list">
      {data.templates.map((template: any) => <article key={template.id}>
        <div><span className={`narrative-status ${template.is_active ? "success" : "warning"}`}>{template.is_active ? "Активен" : "Ожидает"}</span><code>{template.template_type}</code><span className="narrative-source">{template.source}</span></div>
        <p>{template.text_template}</p>
      </article>)}
    </div>}
    {data && data.total > 50 && <nav className="narrative-pagination" aria-label="Страницы шаблонов"><button type="button" onClick={() => setPage(current => Math.max(1, current - 1))} disabled={page === 1}>Назад</button><span>Страница {page} из {pages}</span><button type="button" onClick={() => setPage(current => current + 1)} disabled={data.templates.length < 50}>Вперёд</button></nav>}
  </section>
}

function ImportTab() {
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const [jsonText, setJsonText] = useState("")
  const [defaultType, setDefaultType] = useState("explore")
  const [loading, setLoading] = useState(false)
  const [notice, setNotice] = useState<Notice>(null)
  const applyExample = (example: object[]) => {
    const current = jsonText.trim()
    if (!current) { setJsonText(JSON.stringify(example, null, 2)); return }
    try { const parsed = JSON.parse(current); if (Array.isArray(parsed)) { setJsonText(JSON.stringify([...parsed, ...example], null, 2)); return } } catch { /* replace invalid draft below */ }
    setJsonText(JSON.stringify(example, null, 2))
  }
  const submit = async () => {
    setNotice(null)
    let parsed: any[]
    try { parsed = JSON.parse(jsonText); if (!Array.isArray(parsed)) throw new Error("ожидается JSON-массив") }
    catch (error: any) { setNotice({ kind: "error", text: `Проверьте JSON: ${error.message}` }); return }
    setLoading(true)
    try {
      const result = await api.adminNarrativesImport(parsed.map(item => ({ template_type: item.template_type || defaultType, text_template: item.text_template || item.text || "", source: item.source || "community" })))
      setNotice({ kind: "success", text: `Импорт передан на модерацию: добавлено ${result.imported}.` })
      if (result.imported > 0) setJsonText("")
    } catch (error: any) { setNotice({ kind: "error", text: `Не удалось импортировать: ${error.message || "неизвестная ошибка"}` }) }
    finally { setLoading(false) }
  }
  return <section className="narrative-import" aria-labelledby="import-title">
    <header><span className="narrative-kicker">Пакетная передача</span><h2 id="import-title">Импорт JSON</h2><p>Массив объектов с <code>template_type</code> и <code>text_template</code>. Каждый шаблон идёт в очередь модерации.</p></header>
    <div className="narrative-example-grid">{EXAMPLE_JSON.map(example => <button type="button" key={example.title} onClick={() => applyExample(example.json)}><b>{example.title}</b><span>{example.desc}</span><small>Добавить пример</small></button>)}</div>
    <div className="narrative-import-form"><div><label htmlFor="import-type">Тип по умолчанию</label><TypeSelect id="import-type" value={defaultType} onChange={setDefaultType} /></div><div><label htmlFor="import-json">JSON-массив</label><textarea ref={textareaRef} id="import-json" value={jsonText} onChange={e => setJsonText(e.target.value)} rows={12} spellCheck={false} placeholder={'[{"template_type": "explore", "text_template": "Герой {hero_name} нашёл {discovery}."}]'} /></div></div>
    <VariableRail onInsert={value => { if (textareaRef.current) insertVariable(textareaRef.current, value, setJsonText) }} />
    <button type="button" className="narrative-primary" onClick={submit} disabled={loading || !jsonText.trim()}>{loading ? "Импортируем…" : "Передать на модерацию"}</button>
    <NoticeBox notice={notice} />
  </section>
}

export function NarrativesPage() {
  const isAdmin = useGameStore(state => state.isAdmin)
  const [tab, setTab] = useState<Tab>("vars")
  const tabs: { id: Tab; label: string; description: string; admin?: boolean }[] = [
    { id: "vars", label: "Словник", description: "переменные" }, { id: "create", label: "Создать", description: "шаблон" },
    { id: "suggest", label: "Предложить", description: "редактору" }, { id: "browse", label: "База", description: "шаблоны", admin: true }, { id: "import", label: "Импорт", description: "JSON", admin: true },
  ]
  const visibleTabs = tabs.filter(item => !item.admin || isAdmin)
  return <main className="narratives-observatory">
    <header className="narrative-masthead">
      <div className="narrative-masthead-mark" aria-hidden="true"><span>✦</span><i /></div>
      <div><span className="narrative-kicker">Обсерватория хроник · мастерская летописца</span><h1>Дайте миру фразу,<br /><em>которую он запомнит.</em></h1></div>
      <p>Здесь слова становятся событиями: выберите материал, соберите шаблон и передайте его в летопись.</p>
    </header>
    <nav className="narrative-tabs" aria-label="Разделы мастерской" role="tablist">
      {visibleTabs.map(item => <button key={item.id} type="button" role="tab" aria-selected={tab === item.id} aria-controls={`narrative-panel-${item.id}`} id={`narrative-tab-${item.id}`} onClick={() => setTab(item.id)} className={tab === item.id ? "active" : ""}><b>{item.label}</b><span>{item.description}</span></button>)}
    </nav>
    <section id={`narrative-panel-${tab}`} role="tabpanel" aria-labelledby={`narrative-tab-${tab}`} className="narrative-tab-panel">
      {tab === "vars" && <GlossaryTab />}
      {tab === "create" && <TemplateEditor mode="create" />}
      {tab === "suggest" && <TemplateEditor mode="suggest" />}
      {tab === "browse" && isAdmin && <BrowseTab />}
      {tab === "import" && isAdmin && <ImportTab />}
    </section>
  </main>
}

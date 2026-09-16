# TES Idle — Visual Design Rules (редизайн «Обсерватория», 2026-09)

Дизайн-система после глобального редизайна F-0–F-5 (см. `docs/PLAN_FRONTEND_REDESIGN.md`).
Все страницы используют токены и CSS-классы из `frontend/src/index.css`.

## Themes (две, тёмная — по умолчанию)

```css
/* Тёмная «Ночной уголь» — :root, data-theme="dark" */
--bg: #16110b;        --surface: #1f1811;   --surface-raised: #2a2116;
--fg: #e6d9bd;        --muted: #a08e6f;     --border: #382d1e;
--accent: #c9a227;    --accent-on: #221a06;
--bg-elevated: #241c12; --journal-entry-bg: #241d13;

/* Светлая «Пергамент» — data-theme="light" */
--bg: #f2ecdf;  --surface: #faf6ea;  --fg: #2b2114;  --muted: #7a6b52;
--accent: #8a6d1c;  --accent-on: #fdf9ee;
```

Переключение: `data-theme` на `<html>`, выбор в localStorage (`theme`), инициализация до
первого рендера (без FOUC). `color-scheme` выставляется в CSS по теме.

## HUD-цвета (использовать только их)

| Что | Цвет |
|---|---|
| HP | `--danger` #c0392b |
| MP | `--mp` #3d7dc8 |
| SP | `--success` #5a8a3c (**зелёный**, не оранжевый) |
| XP | `--xp` #8b5cf6 |
| Золото | `--gold` #d4a72c |
| Эпик/божественное | `--epic` #7c5cff |
| Предупреждение | `--warn` #d97706 |

## Typography

- **Display (имена, главы, логотип):** Cormorant Garamond 600/700 — `--font-display`; главы хроники — *italic*.
- **Body:** Inter 400/500/600 — `--font-body`; полная кириллица.
- **Mono (метки, числа):** Fira Code — `--font-mono`, uppercase-метки `letter-spacing: 0.04–0.06em`, числам — `tabular-nums`.
- ❌ **Geist Sans запрещён** — нет кириллицы (русский текст незаметно падал в системный фолбэк).
- Многоточие — символ `…`, не `...`.

## Panel Structure (обязательная для всех карточек)

```html
<div class="panel">
  <div class="panel-header"> <div class="panel-icon">SVG</div> TITLE <span>счётчик</span> </div>
  <div class="panel-body">content</div>
</div>
```
- `border: 1px solid var(--panel-border)`, `border-radius: var(--radius-lg)`, **без box-shadow**
- Header: mono, uppercase, muted; иконки — lucide-react / инлайн SVG со stroke="currentColor"

## Layout

- **Лента:** `[HeroPanel | «Здесь и сейчас» | MoodPanel]` — `1.9fr 1.5fr 1.1fr`
- **Главная сетка `300px 1fr 320px`:** слева — владения героя (Потребности → Питомец → Снаряжение → Инвентарь → Репутация); в центре — Задание над Хроникой; справа — Пульт бога над Миром.
- **Responsive (реальные media queries):** ≤1200px → 2 колонки (герой-лента на всю ширину), ≤920px → 1 колонка. Проверено на 1100/880.
- `prefers-reduced-motion: reduce` отключает декоративные анимации.

## Данные — только настоящие (главное правило)

**Фейковые данных в UI нет и быть не должно.** Заглушки запрещены:
- Нет данных → честный пустой стейт («Репутация чиста. Герой ещё не был замечен…», «Свободен от заданий» + действие).
- Ошибка загрузки → честный стейт ошибки, не молчание и не мок.
- Прогресс/проценты считаются от реальных полей героя, не хардкодом (анти-паттерн: `width: 72%`, `powerPercent = 72`).
- Всё, что приходит с бэка и ещё не подключено во фронте — долг, а не повод рисовать выдумку.

## Component Patterns

- **Статы (HeroPanel):** 4 бара сеткой 2×2 — HP/MP/SP/XP, значения из hero.
- **Хроника-манускрипт:** главы «День N. <фраза>» — Cormorant italic + золотая линия с ромбом (`.journal-chapter-*`); записи — веллум-градиент с цветным кантом по категории (бой=danger, лут=gold, путь=mp, отдых/люди=success, бог=epic, новости=accent); мотивы — курсив «на полях» с пунктиром. Фильтры — семантические категории из 24 entry_type, показываются только присутствующие.
- **Инвентарь:** именованные слоты (иконка + имя 9px + ×N), кант редкости (common/uncommon/rare/epic/legendary → muted/success/mp/epic/gold), клик → карточка с действиями «Использовать» (consumable) / «Выбросить».
- **Квест:** пустой стейт с кнопкой «Попросить задание» (POST /quests/generate).
- **combat_result:** баннер role="status" aria-live="polite" (🏆/💀/🕊️), авто-скрытие 12с.
- **Пульт бога:** реальные `soul_energy`, результат нарративом, кулдаун.
- **Репутация:** уровни из `reputations`-таблицы; EN-ключи (hostile/unfriendly) нормализуются в RU-метки на фронте.

## Accessibility (обязательная)

- Иконочные кнопки — `aria-label` (пример: переключатель темы).
- Формы: `label htmlFor` + `id`, `autocomplete`, `spellCheck={false}` на логинах/почте.
- Фокус: глобальный `:focus-visible { outline: 2px solid var(--accent) }`; не писать `outline: none` без замены.
- `transition` — только конкретные свойства (никаких `transition: all`); анимации только transform/opacity.
- `touch-action: manipulation` на кнопках; модалки — `overscroll-behavior: contain`, `role="dialog"`.

## Font Loading

`@fontsource` локально, дефолтные веса (все сабсеты включая кириллицу):
- `@fontsource/inter` 400/500/600
- `@fontsource/cormorant-garamond` 500/600/700
- `@fontsource/fira-code` 400/500/600

## Theme-change contract

Переключение темы → `window.dispatchEvent(new Event("resize"))` — канвасы (MoodCanvas) перерисовываются
через CSS-var цвета + MutationObserver на `data-theme`. Новые канвасы обязаны читать цвета так же, не хардкодить hex.

## File Structure

- `index.css` — все токены, темы, компонентные классы, responsive, reduced-motion.
- `components/` — единственные источники компонентов (HeroPanel, QuestPanel, JournalPanel, InventoryPanel, …); **инлайн-копии в DashboardPage запрещены** (правило «двух JournalPanel» устарело).
- Страницы — inline-стили для уникального, CSS-классы для повторяющегося.

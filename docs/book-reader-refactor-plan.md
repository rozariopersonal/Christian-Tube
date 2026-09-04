# Book Reader Refactor Plan

## Context

`apps/mobile/lib/features/books/screens/book_reader_screen.dart` is a single
`StatefulWidget` monolith of **2,041 lines** holding **46 state fields**. It
mixes concerns that belong in separate layers:

- Data loading & caching (pages, highlights, TOC, failed-page retry)
- Position tracking (scroll math, GlobalKey bookkeeping, progress persistence)
- Infinite scroll pagination (two-way buffer, load thresholds)
- Dual-page spread layout (page turns, column distribution)
- Reading appearance (themes, fonts, preferences)
- Rendering (paragraph grouping, scripture link spans, highlight overlays)
- Input handling (tap recognizers, selection toolbar, context menus)

This plan splits the reader into single-responsibility controllers, views, and
services so each file stays small, testable, and predictable.

## Design Principles

These apply to the entire refactor and to any future feature in this repo.

### 1. One file, one job (single responsibility)

A Dart file should answer **one** question. If you can't describe a file in a
single sentence without the word "and", split it.

- Corollary: **No monoliths.** A screen widget must be thin: it wires together
  controllers/views and does minimal orchestration. Anything beyond layout and
  `context`-based lookups belongs in a controller or model.
- Hard limit guidance: a screen `*.dart` under `lib/` should rarely exceed
  ~500 lines. If it does, extract a widget sub-tree, a controller, or a
  builder.

### 2. Separate presentational vs. behavioral state

- **Behavioral state** (page index, visibility, progress, highlight ranges)
  lives in a controller (see State Management below), not in widgets.
- **Presentational state** (what a single widget has open, tooltip visibility,
  local drag values) may stay in a widget's local `setState`.
- Rule of thumb: if two widgets need the same value, it does not belong in
  either widget — promote it to the controller.

### 3. Favor composition over inheritance

Build reader features by composing small widgets and controllers rather than
extending a giant base class. Prefer `ValueListenableBuilder` / `AnimatedBuilder`
subscriptions over passing callbacks through many layers when the dependency is
one-directional and many-to-many.

### 4. Thin, dumb widgets; rich, testable logic

Widgets render state; they do not compute it. Move:

- scroll mathematics → `controllers`/`services`
- text parsing & grouping → `services`
- persistence & preference IO → `services` / adapters
- highlight color mapping → `models`/`services`

A widget that contains a `for` loop building `TextSpan`s should probably hand
that off to a builder function in a separate file.

### 5. Controllers expose narrow, observable state

Prefer derived, immutable value objects broadcast via a single `ChangeNotifier`
(or equivalent). Consumers read `controller.state.field` rather than pulling
scattered independent fields. This makes tests deterministic and reduces the
"half-updated state" bugs that plague `setState` monoliths.

### 6. Explicit boundaries between layers

```
View (widgets/*.dart)
  └── reads State from
Controller (book_reader_controller.dart, one per lifecycle)
  └── delegates to
Services (book_service.dart, appearance_service.dart, ...)
  └── talks to
Adapters / Models
```

A widget may only talk to the controller and to `context.tokens`/theme helpers.
It **must not** call `BookService` or `SharedPreferences` directly.

### 7. Keep tests at the boundary that matters most

- Logic (parsers, grouper, position math, appearance prefs) → pure unit tests,
  no widgets.
- Controllers → widget-free tests using `ChangeNotifier` state assertions.
- Views → widget tests at 320/600/840/1400 using fake controllers.
This keeps tests fast and avoids rebuilding the whole screen for every change.

## Target File Layout

`apps/mobile/lib/features/books/`

```
controllers/
  book_reader_controller.dart    # one controller owning reader lifecycle state
  book_reader_appearance.dart    # theme/font/size/line-height + prefs persistence
  reading_progress_controller.dart# position math + save/restore + idle/lifecycle flush

services/
  book_service.dart              # (existing) facade
  book_paragraph_grouper.dart    # (existing)
  scripture_ref_parser.dart      # (existing)
  reading_position_tracker.dart  # visible-page/line math (extracted from _updateVisiblePageAndLine)
  page_loader.dart               # infinite-scroll buffer + dual-page preload (extracted)

screens/
  book_reader_screen.dart        # THIN: assembles controllers + sub-views (target < 500 lines)

widgets/
  book_reader_content.dart       # chooses dual-page vs infinite-scroll via ScreenClass
  infinite_scroll_view.dart      # two-way vertical scroll (current _buildInfiniteScrollView)
  dual_page_spread_view.dart     # side-by-side spread (current _buildDualPageSpreadView)
  reader_page_column.dart        # single page column w/ independent scroll + page number
  reader_navigation_bar.dart     # slider + chevrons + progress (current bottomNavigationBar)
  reader_appbar.dart             # adaptive AppBar (title + highlights/appearance/TOC)
  block_builder.dart             # block-type → widget mapping (from _buildBlockWidget)
  formatted_paragraph.dart       # scripture-link span builder (from _buildFormattedParagraphs)
  appearance_sheet.dart          # settings sheet/dialog (from _showAppearanceSheet)
  highlight_span_builder.dart    # highlight overlay span logic (from _appendSpansWithHighlights)
  reader_state_view.dart         # loading / not-found / retry states
```

## Incremental Migration (safe, keep tests green)

Do not rewrite in one giant diff. Each step lands green and is independently
releasable.

1. **Extract pure logic first** (no behavior change):
   - `reading_position_tracker.dart` — move `_updateVisiblePageAndLine`, `_pruneStaleKeys`.
   - `page_loader.dart` — move page-buffer math, load thresholds, in-flight dedup, failed-page set.
   - Add `book_reader_appearance.dart` — move `_loadAppearancePreferences`,
     `_saveAppearancePreference`, theme mode → `Color` mapping, and add persisted
     `lineHeight`. (Closes fixed-1.65 gap.)
   - Keep the monolith temporarily calling into these extracted services so the
     diff is a pure move.

2. **Introduce `BookReaderController`** holding the 46 fields, wrapping the
   extracted services, exposing one `BookReaderState` `ChangeNotifier`. The
   monolith now reads from the controller instead of local fields. This is the
   risky step — land it in small slices (page state, then progress, then
   appearance).

3. **Extract sub-views** from the monolith's `build` in dependency order
   (leaf-most first): `block_builder`, `formatted_paragraph`,
   `highlight_span_builder`, then `reader_page_column`, then
   `infinite_scroll_view` / `dual_page_spread_view`, then `reader_appbar` and
   `reader_navigation_bar`.

4. **Slim the screen** until `book_reader_screen.dart` only assembles
   controllers + sub-views. Delete dead code and the stale indentation artifact
   at the `_loadBook` region.

5. **Add missing tests** at the new boundaries:
   - controller unit tests (progress save/restore, appearance load/save)
   - `page_loader` buffer tests (load-down threshold, load-up threshold, dedup)
   - dual-page spread widget test at 840/1400
   - highlight create/render test
   - catalog download flow test (referenced repo-standard docs elsewhere)

## Feature Gaps to Close During Refactor

Prioritized:

| Priority | Feature | Where |
|----------|---------|-------|
| 1 | **In-book text search** | new `book_search_sheet.dart` + `book_search_service.dart` |
| 2 | **Highlight color picker** | expose the existing 4-color system in the selection toolbar |
| 3 | **Adjustable line-height** | persist via `book_reader_appearance.dart` |
| 4 | **Bookmarks** | `bookmark` model + toggle in nav bar |
| 5 | **Retry with backoff** | `page_loader.dart` auto-retry policy |

## Conventions Captured Back Into AGENTS.md

The anti-monolith rule below is copied verbatim into `AGENTS.md` so future
agents follow it by default (see "Architecture & Code Organization Standard").

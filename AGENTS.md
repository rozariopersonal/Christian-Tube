# AGENTS.md — Project Standards

Normative rules for all code written in this repository. When a rule is marked
**must**/**must not**, violating it is a bug. These rules are enforced in review
and in widget tests.

## How to use this file

1. Read it before touching UI code.
2. Treat the Responsive & Adaptive UI Standard as the contract for every
   screen, widget, and layout in the Flutter client (`apps/mobile/lib`).
3. When adding a screen or widget, follow the rules below — do not invent a
   private breakpoint scheme or hardcoded size policy.

---

## Responsive & Adaptive UI Standard

The Flutter client ships to Android phones, tablets, and web browsers at any
window size. There is exactly **one** responsive policy, defined here. No
screen may assume a single device size.

### 1. Screen size classes (single source of truth)

Breakpoints are Material 3 WindowSizeClass values on **width**:

| Class      | Width range      | Typical target            |
| ---------- | ---------------- | ------------------------- |
| `compact`  | `< 600`          | Phones portrait           |
| `medium`   | `600 – 839`      | Small tablets, large phones landscape |
| `expanded` | `>= 840`         | Tablets, web, desktop windows |

Rules:

- **Must** use a single shared helper, `ScreenClass.of(context)` (planned as
  `lib/core/layout/adaptivity.dart`), to resolve the class.
- **Must not** inline breakpoint comparisons (`MediaQuery.width > 900 ? ...`)
  in widgets. If a screen needs an extra tier, extend the helper, not the widget.
- **Must** re-evaluate on size change. Use `LayoutBuilder` or
  `MediaQuery.sizeOf` (never `MediaQuery.of(context).size` inside build if a
  rebuild on resize is required).
- Landscape is a window size, not a mode. Navigation and content must remain
  reachable in landscape on any device.

### 2. Navigation shell

`MainLayoutScreen` (`apps/mobile/lib/layout/main_layout_screen.dart`) owns all
shell navigation:

- `compact`: bottom `NavigationBar` (current).
- `medium` / `expanded`: left `NavigationRail` (with a matching drawer fallback).
  The bottom bar **must not** remain visible at these sizes.
- The bottom bar **must not** be hidden in landscape on tablets/web — an
  alternate (rail) must be present there. Hidden nav is only acceptable for
  fullscreen players/shorts (via `BottomBarVisibilityService`).

### 3. Content width — never stretch

- Any scrollable content list that renders text/cards must be constrained to a
  readable measure: **max content width 1080px**, centered, with at most
  `24dp` outer side padding. Apply via a shared `ContentWidth`/`MaxWidthBox`
  helper (planned `lib/core/layout/`), or per-list where simpler.
- **Must not** leave full-width lists/cards on `medium`+ screens (feed,
  search, history, profile, bible, channels, watch relations, bible manager).
- Directly-filling surfaces (video players, shorts grids, scripture cards)
  are exempt from the width cap but not from the grid rules below.

### 4. Grids

- **Must** use `SliverGridDelegateWithMaxCrossAxisExtent` (min tile width) or a
  column count derived from `ScreenClass` — **never** a bare
  `fixedCrossAxisCount` for content that appears on multiple sizes.
- Shorts tiles: target `~150dp` minimum width per cell.
- Video feed: single-column rows on `compact`; 2–3 column grid of compact video
  cards on `medium`+ (a dedicated responsive `VideoCard` variant).
- Recommended min-extent table:
  | Content   | Min tile width |
  | --------- | -------------- |
  | Shorts    | 150            |
  | Feed grid | 320            |
  | Bible manager catalog | 340 |

### 5. Watch / player layout

`VideoPlayerScreen` (`apps/mobile/lib/features/watch/video_player_screen.dart`):

- `compact`: single column — player, then metadata/related below (current).
- `medium`/`expanded`: two-column — player left, description + related list as
  a sidebar on the right. Related rows get a max width via rule 3.
- The player itself must be width-capped (e.g. `maxWidth: 1280`) on large
  screens instead of scaling to fill the window.

### 6. Modals, sheets, dialogs

- Bottom sheets that are >50% of screen height or carry lists:
  **must** be capped at `maxWidth: 640` and centered on `medium`+.
- Small-content prompts (confirmations, single-field forms) on `medium`+ must
  render as centered `AlertDialog`s instead of full-height bottom sheets.
- Sheets/dialogs **must** scroll internally (no fixed-height content that can
  overflow when the keyboard opens or when text scale grows).
- Never use `showModalBottomSheet` with a full screen-height body on large
  screens.

### 7. No overflow tolerances

At a 320dp-wide viewport and the app's max supported text-scale factor,
the following **must not** overflow (`RenderFlex overflow` is a failing test):

- `AppBar` action counts: if `actions` + `title` exceed the width at
  `compact`, collapse trailing actions into an overflow `PopupMenuButton`.
- Rows of mixed `Text` + buttons: use `Flexible`/`Expanded`/`Wrap` — never a
  bare `Row` of intrinsic-width children with a `Spacer` (see current hazards:
  `watch_plans_screen.dart` stats row, `profile_screen.dart` sign-out row,
  `bible_screen.dart` AppBar).
- Overlay HUDs (shorts feeds) must not let floating chips collide with
  floating icons; make such rows horizontally scrollable or merge into one
  `Flexible` row.

### 8. Fonts & density

- Default to `Material 3` `textTheme` via `theme.textTheme`; avoid absolute
  font sizes larger than the surface is comfortable with at 320dp.
- **Must** be compatible with increased system font scale (no fixed-height
  containers around text).
- Scripture/fullscreen card surfaces are allowed their own scaling logic, but
  any `< 13` logical px font is disallowed for body text.

### 9. Land-administered helpers (planned files)

Centralize shared adaptive primitives here rather than per-screen copies:

- `lib/core/layout/adaptivity.dart` — `ScreenClass`, `screenClassOf(…)`,
  grid extent helpers.
- `lib/core/layout/content_width.dart` — `MaxWidthBox` / content wrappers.
- `lib/core/layout/responsive_scaffold.dart` — navigation shell builder
  (NavigationBar vs NavigationRail).
- `lib/core/dimens.dart` — the single set of spacing/radius/min-touch constants
  (replaces scattered literals).

Color tokens are live in `lib/core/theme/app_tokens.dart` (`AppTokens`,
`context.tokens`, `context.isDark`, `context.primary`, `context.accent`). Use
them in every screen (see Theme & Appearance Standard).

### 10. Definition of done for any screen

- Renders without overflow warnings at `320`, `600`, `840`, and `1400`
  logical px in a widget test.
- Uses `ScreenClass` for any conditional behavior.
- No hardcoded `crossAxisCount`; no unbounded `maxWidth`.
- Navigation reachable in landscape.
- Empty/loading/error states match the size rules too.

---

## Theme & Appearance Standard

The Flutter client ships with light, dark, and AMOLED themes plus 7 selectable
accent colors. There is exactly **one** theming policy, defined here. No screen
may hardcode colors or assume a single appearance.

### 1. Single source of truth

- All UI colors **must** come from `Theme.of(context).colorScheme` **or** the
  design-token layer `AppTokens` (`lib/core/theme/app_tokens.dart`), accessed
  via `context.tokens`, `context.isDark`, `context.primary`, `context.accent`.
- **Must not** hardcode raw `Colors.*` or `Color(0x...)` values in screens,
  widgets, or services under `lib/`. The only place that may define literal
  colors is `app_tokens.dart` and `theme_service.dart`.

### 2. Tokens to use

Use the semantic token, never a raw shade:

| Intent            | Token                             |
| ----------------- | --------------------------------- |
| Scaffold bg       | `context.tokens.background`        |
| Card / surface    | `context.tokens.surface`           |
| Subtle fill       | `context.tokens.surfaceVariant`    |
| Hairline border   | `context.tokens.surfaceBorder`     |
| Primary text      | `context.tokens.onSurface`         |
| Secondary text    | `context.tokens.onSurfaceMuted`    |
| Disabled text     | `context.tokens.onSurfaceDisabled` |
| Accent color      | `context.accent` / `tokens.accent` |
| Brand color       | `context.primary`                  |
| Media scrim       | `context.tokens.scrim`             |

Favor `Theme.of(context).colorScheme.*` (e.g. `primary`, `onSurfaceVariant`,
`primaryContainer`) for M3-semantic colors.

### 3. Dark / AMOLED

- `AppTokens.dark` (with `background: black` when AMOLED) is applied
  automatically by `ThemeService`. Do not define separate dark palettes in
  screens.
- **Must not** use `Theme.of(context).brightness == Brightness.dark ? ... :
  ...` ternaries to duplicate the palette; use `context.isDark` only for
  genuinely non-color branching (e.g. icon glyph choice).
- AMOLED must be respected everywhere: surfaces read from `tokens.surface` so
  true black propagates.

### 4. Accent colors

- The 7 `AppColorTheme` accents flow through `colorScheme.primary` and
  `AppConfig.accentColor`. **Must not** reference the fixed default
  blue/amber hexes directly in screens.

### 5. Immersive / media surfaces

- Fullscreen players, shorts, scripture cards, and clip previews may keep a
  dark "immersive" look, but their **chrome** (buttons, labels, scrims) must
  still read from `context.tokens` so a light/future variant is supportable.

### 6. Future screens

- Any new screen/widget must resolve every color through `context.tokens` /
  `colorScheme`. Reuse the token-driven shared widgets in `lib/shared/ui/`
  rather than inventing new color literals. This is enforced in review.

---

## Data Access & Repository Hosting Standard

All remote data assets (Bible versions, library books, cross-references, dictionaries,
study concepts, feeds) are hosted on the public `Christian-Tube-Releases` repository.
Data access must follow this standard across both mobile and web clients.

### 1. Canonical Repository Structure

The releases repository (`Christian-Tube-Releases`) is integrated as a git submodule
at the repository root under `releases/`. Assets must conform to this canonical layout:

```
Christian-Tube-Releases/
├── bibles/
│   ├── bible_{version}.json              # Monolith JSON archive (optional bulk download)
│   ├── {version}/books.json              # Book list & metadata for version
│   └── {version}/{bookNum}/{ch}.json     # Live per-chapter verses (streaming default)
├── books/
│   ├── catalog.json                      # Single common catalog for all languages
│   ├── covers/                           # Book cover art
│   └── {bookId}/                         # Chapters & TOC (or {lang}/{bookId}/)
│       ├── toc.json                      # Table of contents
│       └── chapters/{n}.json             # Chapter content lines
├── cross_references/
│   └── {bookAbbrev}/{chapter}.json       # Pure JSON per chapter e.g. GEN/1.json (streamed, memory-cached)
├── study/
│   └── {version}/                        # Organized by Bible version (e.g. taobvsi/)
│       ├── {version}.sqlite              # Offline SQLite (optional download)
│       └── chapters/b{bb}_c{ccc}.json    # Live per-chapter concepts & definitions
├── commentaries/
│   └── {bookNum}/{chapter}.json          # Zac Poonen book commentaries referencing verses
├── dictionaries/
│   └── dict_{id}.sqlite.gz               # Pre-compiled dictionary SQLite packages
├── words_feed/
│   ├── manifest.json
│   ├── daily.json
│   └── topics/{slug}.json
├── scriptures.json                       # Micro-feed scripture pool
├── book_names.json                       # Localized book names across versions
└── manifest.json                         # Top-level dataset checksums & versions
```

### 2. Single Source of Truth for URLs

- **Must** use `GitHubDataService` (`lib/core/api/github_data_service.dart`) to construct
  any data asset URL.
- **Must not** call `ReleaseAssets.urlsFor(...)` directly from adapters, services, or screens.
- **Must not** hardcode URLs (e.g. `cdn.jsdelivr.net`, `raw.githubusercontent.com`, `api.github.com`)
  or repository names (`rozariopersonal/Christian-Tube-Releases`) in feature code.
- Repository configuration is read dynamically from `AppConfig.releasesRepo` (configured in
  `assets/app_config.json`), making the entire data layer repository-agnostic.
- `ReleaseAssets` automatically provides fallback: jsDelivr edge CDN first (globally cached),
  raw GitHub second.

### 3. Data Access Philosophy: "GitHub-First, Streaming-Default"

- Both web and mobile clients access data live from GitHub CDN by default.
- Downloading to local SQLite is an optional enhancement for offline/airplane use,
  never a blocking prerequisite for reading.
- **Cross-references**: Strictly JSON-only. Served on demand as small (~2–5 KB) per-chapter
  chunks and cached in memory for the session. Storing a 15 MB SQLite database on device
  is eliminated.
- **Commentaries & Backgrounds**: Standalone commentary and background datasets are
  discontinued and superseded by the unified verse study concept engine (`study/{version}/`).
- **Books**: The catalog (`books/catalog.json`) is common and language-agnostic. Book content
  is partitioned cleanly by language code (`books/{lang}/...`).

### 4. Git Submodule Workflow

- The releases repo lives at `releases/`. When updating hosted data assets or binaries:
  1. Make edits and commit inside `releases/`.
  2. Push `releases/` to its remote origin.
  3. Commit the updated submodule pointer in the main repo (`git add releases && git commit`).

---

## Architecture & Code Organization Standard

These rules apply to every feature, screen, and widget added or modified in the
Flutter client (`apps/mobile/lib`). They are enforced in review.

### 1. No monoliths

A screen must be a **thin assembler**: it wires together controllers and
sub-views, and does minimal orchestration. It must not host the full behavior
of the feature in one file.

- A single `*.dart` screen/widget file under `lib/` should rarely exceed
  ~500 lines. If it does, extract a widget sub-tree, a controller, or a
  builder into its own file.
- A `StatefulWidget` `State` class holding a large number of unrelated fields
  (e.g. > ~20) is a smell — split the concern into a controller.

### 2. Single responsibility

A Dart file answers **one** question. If you cannot describe a file in a single
sentence without "and", split it.

### 3. Separate presentational vs. behavioral state

- **Behavioral state** (indices, visibility, progress, selection ranges) lives
  in a controller exposed as observable state — never in widget local state.
- **Presentational state** (a widget's local open/drag/tooltip) may stay in a
  widget's local `setState`.
- If two widgets need the same value, promote it to the controller.

### 4. Thin, dumb widgets; rich, testable logic

- **Must not** put scroll math, text parsing, grouping, persistence, or
  preference IO directly in widgets.
- Move logic to `controllers/` and `services/`; keep widgets to layout +
  `context`-based lookups (`context.tokens`, `theme`, `ScreenClass`).

### 5. Explicit layer boundaries

```
View (screens/ + widgets/)
  └── reads observable state from
Controller (controllers/, one per lifecycle)
  └── delegates to
Services (services/)
  └── talks to
Adapters / Models
```

- A widget **must not** call `BookService`, `SharedPreferences`, or adapters
  directly — go through the controller.
- Widgets read colors via `context.tokens` / `colorScheme` only (see Theme
  Standard).

### 6. Controllers expose narrow, observable state

- Broadcast a single derived immutable value object via `ChangeNotifier` (or
  equivalent). Consumers read `controller.state.field`, not scattered fields.
- This keeps tests deterministic and avoids half-updated-state bugs.

### 7. Test at the boundary that matters most

- Pure logic (parsers, groupers, position math, preference code) → widget-free
  unit tests.
- Controllers → unit tests asserting `ChangeNotifier` state.
- Views → widget tests at 320/600/840/1400 with fake controllers.
- Keep the full suite green after every change (`flutter analyze`,
  `flutter test`).

### 8. Feature layout under `lib/features/<feature>/`

```
feature/
├── adapters/       # data source implementations (platform-specific)
├── controllers/    # state holders / controllers (one per lifecycle)
├── models/         # serializable models
├── screens/        # top-level route screens (thin)
├── services/       # logic, parsing, caching, persistence facades
└── widgets/        # sub-views, presentational components
```

New sub-views, controllers, and services go in their dedicated subfolder — do
not grow `screens/` files into monoliths.

---

## General repository rules

- Run `flutter analyze` and `flutter test` in `apps/mobile` after any UI change;
  keep the full suite green.
- Do not commit generated/platform build artifacts (`apps/mobile/build/`,
  `.dart_tool/`).
- Do not add secrets or config values to source (see
  `scripts/prepare-instance.js` for instance config injection).
- One feature = files under one folder in `lib/features/<feature>/` with
  `screens/`, `widgets/`, `services/` subfolders; shared UI lives in
  `lib/shared/ui/`.
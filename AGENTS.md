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
- Brightness branching on colors is allowed **only inside centralized chrome
  helpers** (see §5). Screens must not duplicate those ternaries inline.
- AMOLED must be respected everywhere: surfaces read from `tokens.surface` so
  true black propagates.

### 4. Accent colors

- The 7 `AppColorTheme` accents flow through `colorScheme.primary` and
  `AppConfig.accentColor`. **Must not** reference the fixed default
  blue/amber hexes directly in screens.
- `ThemeService` sets `tokens.accent` to the selected `AppColorTheme` color, so
  `context.accent` / `tokens.accent`, `colorScheme.primary`, and verse/book
  highlights follow the accent picker together. **Must not** override
  `secondary` with a separate `accentColor` in theme construction.

### 5. Immersive / media surfaces

- Fullscreen players, shorts, scripture cards, and clip previews may keep a
  dark "immersive" look for the **media itself** (video frames, thumbnails,
  playback surfaces) — that stays `scrim`.
- Their **chrome** (buttons, labels, HUD gradients, scrims behind pills/chips)
  must still be theme-aware through a shared helper so the light theme is not
  black. Do this with the `ShortsChrome` extension
  (`lib/features/shorts/widgets/shorts_chrome.dart`, public shared pattern):
  - `shortsChromeBg` — dark: `scrim`, light: `surface`
  - `shortsChromeFill` — dark: `scrim`, light: `surfaceVariant`
  - `shortsChromeFg` — dark: `onScrim`, light: `onSurface`
  - `shortsChromeFgMuted` — dark: `onScrimMuted`, light: `onSurfaceMuted`
  - `shortsChromeShadow` — dark: `scrim`, light: `surfaceBorder`
  - `shortsBottomGradient` — 5-stop bottom gradient (scrim in dark, surface in light)
- Whole-surfaces hosting shorts/flows (grid/feed Scaffolds) use
  `tokens.background`, not `scrim` — only the media itself is exempt.
- **Must not** fall back to raw `Colors.black`/`Colors.white` (e.g. luminance
  text on accent) — resolve through `tokens.scrim`/`tokens.onSurface`.

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
│   ├── {version}/counts.json             # Per-chapter verse-row counts (scroll index)
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
├── songs/
│   ├── catalog.json                      # Live JSON catalog (streaming default)
│   └── songs.sqlite.gz                   # Prebuilt SQLite with FTS5 search (optional download)
├── words_feed/
│   ├── manifest.json
│   ├── daily.json
│   └── topics/{slug}.json
├── fonts/
│   └── {Family}_{File}.ttf              # On-demand reader fonts (SIL OFL), never bundled in the app
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

### 4. Asset Revision & Cache Busting

Static assets (book covers, fonts, audio art) are served from immutable-looking
URLs, but the client caches them **by URL** (`CachedNetworkImage` disk cache and
CDN edge caches). Replacing a file in place (same path, same branch) does **not**
reach existing installs — the old bytes keep being served from local cache.

Rules:

- The top-level `releases/manifest.json` owns a `revision` field — the single
  version token for the whole dataset. Keep it unique per release.
- **Must** bust asset caches via that revision: `ReleaseAssets.urlsFor(...)`
  appends `?rv=<revision>` to every candidate URL. When `manifest.json`'s
  `revision` is bumped on a data push, all asset URLs change and caches refetch
  without an app release.
- **Must** bump `revision` in `releases/manifest.json` whenever hosted data or
  binaries change (covers, fonts, catalog, chapters, feeds, audio, sqlite
  packages). A commit that changes data but not the revision is a bug: installs
  will keep showing stale assets.
- **Must not** change cached asset filenames or directory structures as a
  substitute for bumping the revision.
- The client resolves the revision through `ReleaseRevision.load()` (`lib/core/
  api/release_revision.dart`), called in `main()` before `runApp`. It seeds from
  `SharedPreferences` (offline-safe) then refreshes from the live manifest with a
  bounded timeout. Never block: failures fall back to the last-known revision
  and are non-fatal.
- The manifest fetch itself strips the `?rv=` query so it can always resolve the
  newest revision.

### 5. Git Submodule Workflow

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

## Testing & Quality Gate Standard

Every change to the Flutter mobile client is subject to a 3-tier quality gate locally and in GitHub Actions CI. Violating these rules will fail the CI release gate.

### 1. Tiered Quality Gate Architecture & Testing Philosophy

**Testing Philosophy**:
- **Must** use E2E Maestro tests (`.maestro/`) exclusively for **important user actions** and critical path journeys (e.g. video playback, Bible navigation, auth).
- **Must** use Flutter unit and integration tests (`apps/mobile/test/`) for all **minor behaviors, edge cases, state management, and utility functions**.

1. **Gate 1 (Code & Unit Quality Gate)**:
   - **Must** pass `flutter analyze --no-fatal-infos` with zero errors or fatal issues.
   - **Must** pass all unit, widget, and adaptivity tests (`flutter test`) in `apps/mobile/test/`.
   - **Must** keep the entire test suite green after every change.

2. **Gate 2 (APK Compilation)**:
   - Obfuscated release builds must compile cleanly for all active instances (`christian_tube`, `centum_academy`).

3. **Gate 3 (E2E Smoke & APK Verification Gate)**:
   - Core flows and navigation shell changes must pass Maestro E2E tests on the compiled APK (`.maestro/smoke_flow.yaml`).
   - Run tests locally using `.\scripts\test-e2e.ps1` (Windows) or `./scripts/test-e2e.sh` (macOS/Linux).
   - E2E tests run against a running emulator or connected device via `adb`.

### 2. E2E Test Flows in `.maestro/`

- Declarative YAML flows live in `.maestro/`.
- `smoke_flow.yaml` validates cold-boot, main shell navigation (Words, Audio, Bible, Profile), content feed loading, and in-app update checking.
- `google_auth_flow.yaml` validates native Google Sign-In interaction using a pre-authenticated emulator snapshot without 2FA/CAPTCHA blockage.
- When adding a new primary user flow, add or update a corresponding flow in `.maestro/`.

### 3. Agent Branching & Local Test Standard

- **Dedicated Branch per Task**: Agents and developers **must not** commit or push directly to `main` or `develop`. Every task must be performed on an isolated branch created from `develop`:
  ```bash
  git checkout develop
  git pull origin develop
  git checkout -b agent/<short-task-name>
  ```
- **Mandatory Unit & E2E Testing**:
  - Every agent adding or modifying logic **must** add corresponding unit and widget tests in `apps/mobile/test/`.
  - If introducing or modifying a critical user flow, the agent **must** add or update the declarative Maestro flow in `.maestro/`.
- **Local Pre-Push Verification**:
  Before pushing to their branch or opening a PR, agents **must** run the local verification suite:
  1. `flutter analyze --no-fatal-infos` (must pass with zero errors)
  2. `flutter test` (all unit and widget tests must pass)
  3. `.\scripts\test-e2e.ps1` (Windows) or `./scripts/test-e2e.sh` (macOS/Linux) against a running emulator or connected device.
- **Conventional Commits & Release Notes**:
  All commits by agents **must** use Conventional Commits so that automated release notes accurately describe the changes to users:
  - `feat(<scope>): <user-facing description>` for new features (e.g. `feat(channels): add search and subscription filtering`).
  - `fix(<scope>): <description of fix>` for bug fixes (e.g. `fix(bible): resolve note editor save error`).
  - `perf(<scope>): <optimization>` for speed/rendering improvements.
  - Vague commits like `wip`, `update`, `fix`, or `changes` **must not** be used.
  - If a task involves complex multi-commit changes, the agent may include a root `RELEASE_NOTES.md` file summarizing highlights for the release notes generator.
- **Push, PR & Mandatory Auto-Merge Ownership**:
  - Once local verification passes, agents **push their branch** and **raise a Pull Request** targeting `develop`:
    ```bash
    git push -u origin agent/<short-task-name>
    gh pr create --base develop --title "<type>(<scope>): <summary>" --body "<details>"
    ```
  - **Ownership Until Auto-Merged (CRITICAL)**:
    An agent **must not** declare a task done merely by raising a PR. Agents have full end-to-end ownership of their PR:
    1. The agent **must** monitor PR quality checks (`gh pr checks <pr_number>`).
    2. If any check fails (static analysis, unit tests, widget tests, workflow actions, or environment configuration):
       - The agent **must** inspect the failure logs (`gh run view <run_id> --log-failed`).
       - The agent **must** fix the root cause inside its worktree branch (even if the fix requires updating GitHub Actions workflows or test lifecycles).
       - Commit, push, and monitor until all checks pass green.
    3. **Definition of Done**: A task is strictly considered **DONE** only when the PR Quality Gate passes green and the PR is successfully **auto-merged into `develop`**.
  - **Automated Merge**: The PR Quality Gate workflow (`pr_validation.yml`) automatically tests the PR. When all static analysis and unit tests pass, the PR is automatically merged into `develop` without human intervention.
  - **Automated Beta Release**: Merging into `develop` automatically triggers the Beta pipeline (`release.yml`), creating a badged Beta APK, running Maestro smoke tests, and publishing a GitHub pre-release (`vX.Y.Z-beta.N`).
  - Only vetted release promotions merge from `develop` into `main`.

---

## Branching & Release Channels Standard

The repository operates on a two-channel release strategy: **Beta** (integration) and **Production** (stable).

### 1. Dual-Track Branches
| Branch | Role | Quality Gate & Release Action |
| :--- | :--- | :--- |
| `develop` (Default) | Active integration & Beta releases | On merge: runs unit & smoke tests, builds Beta APKs, auto-tags `vX.Y.Z-beta.N`, and publishes as a GitHub Pre-release. |
| `main` (Protected) | Stable production releases | On merge: runs full validation suite, builds production APKs, auto-tags `vX.Y.Z`, and publishes official GitHub Release to all users. |
| `agent/*`, `feat/*` | Isolated work branches | PR checks run static analysis and unit tests (`pr_validation.yml`). |

### 2. Side-by-Side App Installations (Beta vs. Production)
Beta and Production builds are completely isolated applications on Android:
- **Production**:
  - `applicationId`: `org.rozario.christiantube.mobile`
  - `appName`: `ChristianApp`
  - `apkFileName`: `christian-app.apk`
  - Launcher Icon: Clean original logo.
- **Beta**:
  - `applicationId`: `org.rozario.christiantube.mobile.beta`
  - `appName`: `ChristianApp Beta`
  - `apkFileName`: `christian-app-beta.apk`
  - Launcher Icon: Features a high-contrast **"BETA"** badge overlay dynamically generated by `scripts/generate-icons.py`.
- Users and developers may have **both** Beta and Production installed concurrently on the same physical device without database, preference, or cache collisions.
- The in-app update service (`UpdateService`) queries `/releases` for Beta installations to find newer pre-releases (`vX.Y.Z-beta.N`) and `/releases/latest` for Production installations.

### 3. Scope & Path Filtering for Mobile CI/CD
To prevent unnecessary CI load and false releases when working on backend or background services, mobile CI/CD pipelines are strictly path-filtered:
- **Filtered Paths**:
  - `apps/mobile/**`
  - `scripts/**`
  - `.github/workflows/release.yml` and `.github/workflows/pr_validation.yml`
  - `releases/**` (remote assets submodule)
  - `package.json`
- **Behavior**:
  - `release.yml` and `pr_validation.yml` only trigger when files under the above paths are touched.
  - Changes strictly inside `apps/backend/**`, `services/**`, documentation, or database schemas do not invoke mobile test or APK compilation workflows.

---

## Parallel Agent Execution & Git Worktree Standard

When multiple autonomous or human agents work concurrently on the repository, they **must not** share or switch branches in the primary workspace root (to prevent unstaged file collisions, submodule checkout race conditions, and interrupted runs).

### 1. Worktree Helper Scripts
The repository provides cross-platform worktree management scripts:
- Windows (CMD / PowerShell): `.\scripts\worktree.bat <command>`
- macOS / Linux: `./scripts/worktree.sh <command>`

All worktrees reside under `.worktrees/<task-name>/` (which is git-ignored along with `.codex/`).

### 2. Available Commands
| Command | Action |
| :--- | :--- |
| `.\scripts\worktree.bat create <task-name>` | Fetches latest `origin/develop`, creates an isolated worktree at `.worktrees/<task-name>/`, checks out a fresh tracking branch `agent/<task-name>`, initializes submodules, and runs `flutter pub get`. |
| `.\scripts\worktree.bat list` | Lists all active git worktrees and their associated branches across the repository. |
| `.\scripts\worktree.bat remove <task-name>` | Deletes the worktree directory, unregisters it from git, and deletes the local branch `agent/<task-name>`. |
| `.\scripts\worktree.bat prune` | Prunes any stale or orphaned worktree references. |

### 3. Agent Lifecycle in Worktrees
1. **Initialize**:
   ```bash
   .\scripts\worktree.bat create <short-task-name>
   cd .worktrees\<short-task-name>
   ```
2. **Develop & Test**:
   Make edits, implement unit tests, and verify locally inside the worktree directory:
   ```bash
   cd apps/mobile
   flutter analyze --no-fatal-infos
   flutter test
   ```
3. **Commit & Push**:
   ```bash
   git add <files>
   git commit -m "<type>(<scope>): <message>"
   git push -u origin agent/<short-task-name>
   ```
4. **Raise PR**:
   ```bash
   gh pr create --base develop --title "<type>(<scope>): <message>" --body "<details>"
   ```
5. **Monitor Checks & Fix Issues until Auto-Merged**:
   - Track PR checks: `gh pr checks <pr-number>`.
   - If any check fails, inspect logs (`gh run view <run-id> --log-failed`), resolve the root cause inside the worktree, commit, and push.
   - Repeat until the PR Quality Gate passes green and auto-merges into `develop`.
6. **Clean Up**:
   Return to the main repository root and remove the temporary worktree only after the PR is successfully merged into `develop`:
   ```bash
   cd ..\..
   .\scripts\worktree.bat remove <short-task-name>
   ```

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
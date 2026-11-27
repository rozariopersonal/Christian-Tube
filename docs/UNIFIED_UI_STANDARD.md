# Unified UI Standard — Web (`apps/web`) & Mobile (`apps/mobile`)

> **Status:** Approved Standard  
> **Scope:** `apps/mobile/lib` (Flutter) and `apps/web/src` (Angular)  
> **Goal:** Near-1:1 visual, behavioral, and structural parity across mobile devices, mobile web viewports (`< 600px`), tablets (`600–839px`), and desktop browsers (`>= 840px`).

---

## 1. Design Tokens & Color System

Both platforms **must** share an identical semantic token contract (`AppTokens` in `apps/mobile/lib/core/theme/app_tokens.dart` and CSS custom properties in `apps/web/src/styles.css`). Feature code **must never** hardcode raw hex colors, `Colors.*`, or `#fff` / `#000` literals.

### 1.1 Semantic Color Tokens

| Token (Flutter `context.tokens.*`) | Token (Web CSS) | Light | Dark (Slate) | Dark (AMOLED) |
| --- | --- | --- | --- | --- |
| `background` | `--bg` | `#F8FAFC` | `#0F172A` | `#000000` |
| `surface` | `--surface` | `#FFFFFF` | `#1E293B` | `#0A0A0A` |
| `surfaceVariant` | `--surface-variant` | `#F1F5F9` | `#1E293B` | `#141414` |
| `surfaceElevated` | `--surface-elevated` | `#F8FAFC` | `#283548` | `#1C1C1C` |
| `surfaceBorder` | `--surface-border` | `rgba(0,0,0,0.12)` | `rgba(255,255,255,0.12)` | `rgba(255,255,255,0.14)` |
| `onSurface` | `--on-surface` | `rgba(0,0,0,0.87)` | `#FFFFFF` | `#FFFFFF` |
| `onSurfaceMuted` | `--on-surface-muted` | `rgba(0,0,0,0.54)` | `rgba(255,255,255,0.60)` | `rgba(255,255,255,0.60)` |
| `onSurfaceDisabled` | `--on-surface-disabled` | `rgba(0,0,0,0.38)` | `rgba(255,255,255,0.38)` | `rgba(255,255,255,0.38)` |
| `accent` | `--accent` | Dynamic (default `#3B82F6`) | Dynamic (default `#3B82F6`) | Dynamic (default `#3B82F6`) |
| `scrim` | `--scrim` | `#000000` | `#000000` | `#000000` |
| `onScrim` | `--on-scrim` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` |
| `onScrimMuted` | `--on-scrim-muted` | `rgba(255,255,255,0.70)` | `rgba(255,255,255,0.70)` | `rgba(255,255,255,0.70)` |

### 1.2 Accent Palette (7 Themes)

Both `AppColorTheme` (`theme_service.dart`) and `APP_COLOR_THEMES` (`theme.service.ts`) share the exact 7 accents, with **Sapphire Blue (`#3B82F6`)** as the unified default:

- Sapphire Blue: `#3B82F6`
- Royal Crimson: `#DC2626`
- Emerald Green: `#10B981`
- Violet Purple: `#8B5CF6`
- Warm Amber: `#F59E0B`
- Rose Pink: `#EC4899`
- Cyan Teal: `#06B6D4`

**Rule:** `AppTokens.light.accent` and `AppTokens.dark.accent` fallbacks must also default to `#3B82F6` (not `#F59E0B`) so isolated tests and fallback themes match `ThemeService`.

---

## 2. Typography & Font Loading

### 2.1 Font Families

- **Body / UI Default:** `Inter` (`14px` base, `1.45` line-height).
- **Display / Brand Headers:** `Outfit` (weight `600–700`, tight tracking `-0.3px` to `-0.5px`).
- **Selectable UI Fonts (`APP_FONT_FAMILIES`):** `Inter`, `Outfit`, `Roboto`, `Poppins`, `Nunito`, `Playfair Display`.
  - **Web Requirement:** All 6 UI fonts must be loaded (or dynamically injected via Google Fonts stylesheet on selection) in `apps/web` so selecting `Roboto`, `Poppins`, `Nunito`, or `Playfair Display` in Settings does not silently fall back to `system-ui`.
- **Reader Fonts:** Managed by `ReaderAppearance` / `ReaderAppearanceService` (`Playfair` default at `17px`, line-height `1.65`, range `14–26px`) with on-demand `.ttf` loading from `releases/fonts/`.

### 2.2 Type Scale

| Role | Size | Weight | Notes |
| --- | --- | --- | --- |
| Brand / Tab Hero Header | `20px` | `700` | `Outfit`, `-0.4px` tracking |
| Standard AppBar / Sheet Title | `18px` | `600` | Flush left (`16px` margin) |
| Section Heading | `16px` | `600–700` | — |
| Card Title | `14–15px` | `600` | Max 2 lines with ellipsis |
| Body / Interactive Chip | `13–14px` | `400–500` | Never `< 13px` for body or interactive controls |
| Metadata / Timestamp / Badge | `11–12px` | `500–600` | `onSurfaceMuted` or `onScrim` |

---

## 3. Layout, Breakpoints & Spacing

### 3.1 Breakpoints (Single Source of Truth)

Both `ScreenClass` (`adaptivity.dart`) and `ScreenClassService` (`screen-class.service.ts`) must use:

| Class | Width | Target |
| --- | --- | --- |
| `compact` | `< 600px` | Phones & mobile web |
| `medium` | `600px – 839px` | Small tablets, landscape phones |
| `expanded` | `>= 840px` | Tablets, desktop browsers |

- **Action Collapse Threshold:** `< 360px` collapses secondary AppBar/toolbar actions into an overflow menu (`needsCollapsedActions`).
- **No Ad-Hoc Breakpoints:** Remove component-specific CSS breakpoints (`720px`, `900px`) in favor of `ScreenClassService`.

### 3.2 Content Width & Outer Margins

- **Mobile (`apps/mobile`):** `1080px` max readable content width (`MaxWidthBox`), centered (per `AGENTS.md`), with `1600px` optional ultra-wide cap for multi-column grids.
- **Web (`apps/web`):** Full-bleed `.max-width-box` (`width: 100%`, no `1080px` cap) so pages fill the viewport without empty side margins, while keeping `1280px` max-width on the watch theater frame and `640px` max-width on modal dialogs.
- **Outer Side Padding:** `16px` on `compact`, `24px` on `medium` and `expanded` (never `12px` or `20px` per-screen).

### 3.3 Spacing & Border Radii

| Token | Value | Usage |
| --- | --- | --- |
| `xs` / `--space-xs` | `4px` | Tight icon/label gaps |
| `sm` / `--space-sm` | `8px` | Compact list gaps, `--radius-sm` (small badges/inputs) |
| `md` / `--space-md` | `12px` | Grid gutters, `--radius-md` (compact cards, thumbnails, media tiles) |
| `lg` / `--space-lg` | `16px` | Standard padding, `--radius-lg` (primary surface cards, sheets) |
| `xl` / `--space-xl` | `24px` | Section gaps, medium+ outer padding |
| `pill` / `--radius-pill` | `9999px` | Pills, search bars, filter chips, floating Bible bottom nav |

### 3.4 Responsive Grid Extents

All grids must use auto-fill / max-cross-axis-extent (never hardcoded `crossAxisCount`):

| Content Type | Min Tile Width | Aspect / Card Style |
| --- | --- | --- |
| Video Feed (`medium`+) | `300px` | `16:9` thumbnail (`12px` radius) + channel avatar + 2-line title |
| Shorts Grid | `155px` | `9:16` poster (`12px` radius), `scrim` bottom gradient, `onScrim` text |
| Books Catalog | `160px` | Cover (`8–12px` radius), download/progress indicator |
| Audio Series Grid | `170px` | `1:1` cover (`14px` radius), bottom `scrim` gradient, `onScrim` text |
| Channels Grid | `320px` | Surface card (`16px` radius, `surfaceBorder`) |

---

## 4. Navigation Shell & Back Behavior

### 4.1 Shell Chrome by Screen Class

- **`compact` (`< 600px`)**:
  - **Bottom Navigation Bar** (`60–64px` height, `tokens.background` / `--bg`, `1px` top `surfaceBorder`, no pill background indicator, accent active icon/label).
  - **Root Tabs (5–6 max, no horizontal scrolling):** `Feed` (`/feed`), `Shorts` (`/shorts`), `Bible` (`/bible`), `Library` (`/library` — hub for Books, Articles, Songs), `Words` (`/words`), `Audio` (`/audio`).
  - Web compact view (`MainShellComponent` `COMPACT_BOTTOM_NAV` + `More` sheet, or `Library` hub) keeps 5 non-scrolling bottom slots matching mobile; `Books`, `Articles`, `Songs`, `Audio`, `Channels`, `Subscriptions`, `History`, `Watch Later`, and `Settings` remain reachable without horizontal scrolling.
  - **Compact Account / Search Header:** Web compact pages should render `<app-account-avatar-menu />` (parity with mobile's `SyncAvatarButton` in `VideoFeedScreen`) rather than plain `/settings` links.
- **`medium` (`600–839px`) & `expanded` (`>= 840px`)**:
  - **Mobile (Flutter):** Left `NavigationRail` (`76px` width, root tabs).
  - **Web (Angular):** Retains the existing web topbar (`56px` with centered search, theme toggle, account avatar) + collapsible left rail (`72px`) / drawer (`240px` on `medium`, `232px` expanded sidebar on `expanded`), with direct links for Books, Articles, Songs, Channels, Subscriptions, History, Watch Later, and Settings.

### 4.2 Back Navigation

- **No On-Screen Back Arrows:** `automaticallyImplyLeading: false` enforced globally in `ThemeService.appBarTheme` (mobile) and no back chevrons in web headers.
- Mobile uses `ShellBackHandler` + `NavigationHistoryService`; web uses browser history + top-level shell navigation.

---

## 5. Unified UI Controls & Component Contracts

### 5.1 Bible Version Picker (`BibleVersionPickerSheet` / `app-bible-version-picker`)

Replaces multi-select-by-default row taps with **one unified picker** across both platforms:

1. **Trigger:** `BibleVersionPill` / `.version-trigger` (`radius-pill`, `accent` border + soft accent fill, book icon + version code + native script + dropdown chevron).
2. **Default Tap Behavior (Single-Select):** Tapping anywhere on a version row **selects that single translation** as the active primary version (`comparisons: []` or closes the picker immediately).
3. **Optional Multi-Select / Parallel Mode:** When `maxSelections > 1` (e.g. `BibleReaderComponent`, `WordsFeedComponent`), each version row includes an optional **checkbox on the right edge**. Tapping the checkbox toggles that version into/out of parallel comparison mode (up to 3 total) without closing the sheet or changing the single-tap default.
4. **Context Isolation:** `BibleSearchSheetComponent` and `BibleSearchPageComponent` must use an isolated `contextKey` (e.g. `'bible-search'`, never `'bible'`) with `maxSelections = 1` so searching never wipes the reader's parallel comparison list.
5. **Sheet Contents:** Shared `SearchInputComponent` / search bar (`Search versions or languages...`), Frequently Used / Selected chips, Recently Used chips, and all catalog translations grouped by language (with offline/downloaded badge on mobile).

### 5.2 Search Inputs

All search inputs (global topbar, compact page headers, modal sheets) must use:
- Pill shape (`--radius-pill` / `StadiumBorder`), `40–42px` height
- `--surface-variant` (`tokens.surfaceVariant`) fill with `1px solid --surface-border`
- Leading `search` icon (`onSurfaceMuted`) and trailing clear (`close`) button when non-empty

### 5.3 Cards

- **Surface Cards** (Channels, Articles, Songs, Settings groups, Empty/State cards):
  - Background: `tokens.surface` (`--surface`)
  - Border: `1px solid tokens.surfaceBorder` (`--surface-border`)
  - Radius: `16px` (`--radius-lg`) for primary cards, `12px` (`--radius-md`) for compact rows/tiles
  - Elevation: `0` (use border, not drop shadows, in both light and dark)
- **Media Overlay Cards** (Shorts, Audio Series):
  - Gradient & badge fills must use `tokens.scrim` (`--scrim`) and `tokens.onScrim` (`--on-scrim`) — never raw `Colors.black` or `#000000`.

### 5.4 Modals, Sheets & Dialogs

- **Compact (`< 600px`):** Bottom sheet (`24px` top radius, drag handle, `surface` background, internal scroll, keyboard `viewInsets` padding).
- **Medium / Expanded (`>= 600px`):** Centered dialog (`maxWidth: 640px` for lists/forms, `420px` for confirmations, `maxHeight: 85–90dvh`, `surface` background, `surfaceBorder` hairline).
- **Web Rule:** Every modal/dialog (`Channels`, `AdminUsers`, `WatchVideo` share, `Settings` feedback, `LanguageDropdown`) must use `<app-modal-sheet>` instead of custom `.confirm-backdrop` / `.modal-panel` duplicates.

### 5.5 Reader Toolbars (Bible, Book, Article)

- **Compact (`< 600px`):** Sticky `52–56px` bar with `version/title` pill, `chapter/TOC` nav pill (`--radius-sm`), and trailing action icons collapsing into an overflow menu below `360px`.
- **Medium / Expanded (`>= 600px`):** Controls dock cleanly in the topbar/AppBar; floating `exit-focus-btn` renders **only** when `immersive()` is `true`.

### 5.6 Loading & Empty States

- **Loading:** Shimmer/skeleton placeholders matching card geometry (not plain `"Loading..."` text).
- **Empty / Error:** Centered bordered `.state-card` (`maxWidth: 420px`, `surface`, `surfaceBorder`, `16px` radius, icon + title + muted subtitle + optional primary action pill).

---

## 6. Phased Implementation Plan (Baseline: `develop` @ `bd24849`)

### Phase 1 — Tokens, Typography, Colors & Layout Foundations
1. **Color & AMOLED Parity:**
   - Update `AppTokens.light.accent` and `AppTokens.dark.accent` in `apps/mobile/lib/core/theme/app_tokens.dart` to `#3B82F6`.
   - Align AMOLED tokens across `apps/mobile/lib/core/theme/theme_service.dart` and `apps/web/src/styles.css` (`#000000` / `#0A0A0A` / `#141414` / `#1C1C1C`), and fix `theme_service.dart` `darkTheme` hardcoded `Colors.white`/`Colors.white60`.
   - Replace hardcoded `Colors.black`/`Colors.white` in mobile audio cards (`audio_series_card.dart`, `audio_series_carousel.dart`, `audio_track_list_tile.dart`, `audio_series_header.dart`, `audio_continue_listening_card.dart`, `audio_grouped_sections.dart`, `playback_queue_sheet.dart`), `profile_screen.dart` (`onScrim` on history duration badge), and admin/onboarding/feedback sheets with `context.tokens`.
   - Fix undefined CSS variables in `apps/web/src/app/shared/ui/note-editor-modal.component.ts` (`--bg-surface`, `--text-primary`, `--border-subtle`, `--text-secondary`, `--bg-canvas` -> `--surface`, `--on-surface`, `--surface-border`, `--on-surface-muted`, `--surface-variant`).
   - Replace hardcoded `#fff`/`#ffffff`/`#0f172a` in web `WordsFeedComponent`, `ShortsComponent`, `BibleSidebarComponent`, `AccountAvatarMenuComponent`, `BibleVersionPickerComponent`, `WordsFilterDrawerComponent`, and `WordsStyleDrawerComponent` with `--scrim`/`--on-scrim`/`--on-accent`/`--surface`.
2. **Typography & Web Font Loading:**
   - Load all 6 `APP_FONT_FAMILIES` (`Inter`, `Outfit`, `Roboto`, `Poppins`, `Nunito`, `Playfair Display`) in `apps/web/src/index.html` (or dynamically on selection).
   - Unify mobile AppBar title scale (`18px` standard / `20px` `Outfit` branded) and remove hardcoded `GoogleFonts.outfit` in `ChannelsScreen`/`AdminUsersScreen`.
   - Audit sub-`13px` interactive chip labels (`FontBrowserView` `12px` chips, `VideoFeedScreen` `12px` pill) and fix mojibake in `article_reader_screen.dart:111`.
3. **Layout, Spacing & Breakpoints:**
   - Keep `.max-width-box` full-bleed on web (`width: 100%`) while preserving `MaxWidthBox` (`1080px`) on mobile.
   - Replace ad-hoc breakpoints (`720px` in `ChannelDetailComponent`, `900px` in `ReaderTypographyToggleComponent` on web; `560px` in `FullscreenShortsPlayer` and `720px` in `VideoPlayerScreen` on mobile) with `ScreenClassService` / `ScreenClass.of(context)`.
   - Adopt `AppDimens` (`apps/mobile/lib/core/dimens.dart`) across mobile screens and unify pill radius (`--radius-pill: 9999px` / `StadiumBorder`).

### Phase 2 — Navigation Shell & Feature Parity
1. **Web Shell & Compact Nav (`< 600px`):**
   - Add a `Library` hub page (`/library`) on web grouping Books, Articles, and Songs; add `Songs` (`/songs` & `/song/:id`) to `apps/web` with full parity to mobile.
   - Add `/subscriptions` to `MainShellComponent` sidebar (`YOU_NAV`) and `MORE_SHEET_LIBRARY`.
   - Use `<app-account-avatar-menu />` in `VideoFeedComponent` `.compact-bar` (matching mobile `SyncAvatarButton`).
2. **Mobile Back-Arrow & Navigation Fixes:**
   - Set `automaticallyImplyLeading: false` globally in `ThemeService.lightTheme.appBarTheme` / `darkTheme.appBarTheme` and explicitly on `ProfileScreen`, `VideoFeedScreen`, and `BibleAppBar`.
   - Replace direct `SystemNavigator.pop()` in `OnboardingScreen` with `ShellBackHandler` / safe exit handling.

### Phase 3 — Unified UI Controls, Bug Fixes & Reader Polish
1. **Unified Bible Version Picker (Web & Mobile):**
   - Update `BibleVersionPickerComponent` (`apps/web/src/app/shared/ui/bible-version-picker.component.ts`) and `BibleVersionSelectionService` so tapping a version row **selects that single version** as primary and closes the dropdown, while an optional **checkbox on the right** toggles parallel comparison (up to 3).
   - Add optional right-side parallel checkbox support to mobile `BibleVersionPickerSheet` (`apps/mobile/lib/shared/ui/bible_version_picker_sheet.dart`) where parallel mode is supported.
   - Fix `BibleSearchSheetComponent` sharing `contextKey="bible"` (change to `'bible-search'`), fix dead `showVersionPicker` button in compact `BibleSearchPageComponent`, and remove orphaned `BibleVersionSheetComponent` / `BibleParallelSheetComponent`.
2. **Duplicate Controls & Overlay Bug Fixes (Web & Mobile):**
   - Fix `VideoCardComponent` duplicate `Watched` badge (remove old `.watched-badge`, keep `<app-video-watched-overlays>`).
   - Fix `VideoFeedComponent` `.shelf-thumb-wrap` missing `position: relative`, and `ShortsComponent` `.progress-track` hidden behind `.short-scrim` (`z-index`).
   - Remove duplicate `Liked` filter chips in `VideoFeedComponent` (web & mobile) and duplicate Like buttons (`favorite` + `thumb_up`) in `WatchVideoComponent` and `ShortsComponent`.
3. **Modals, Search Bars & Readers:**
   - Route `NoteEditorModalComponent`, `ChannelsComponent`, `AdminUsersComponent`, `WatchVideoComponent`, `SettingsComponent`, and `LanguageDropdownComponent` modals through `<app-modal-sheet>`, and use `showAdaptiveBottomSheet` in mobile `ShortsChannelFilterSheet` and `AccountSyncPanel`.
   - Standardize compact search inputs across web to `<app-search-input />` (`--radius-pill`).
   - Fix `BibleReaderComponent` double toolbar at `600–1023px` (guard `.bible-bar` with `screen.isCompact()`), fix `exit-focus-btn` contrast (`color: var(--on-surface)`) and `@else if (immersive())` guard across `BibleReaderComponent`, `BookReaderComponent`, and `ArticleReaderComponent`.
   - Remove dead `ShortsGridScreen` on mobile; standardize skeleton loaders & `.state-card` empty states.

### Phase 4 — Verification & Merge
- **Mobile:** `flutter analyze` and `flutter test`.
- **Web:** `npx ng test` / `npm run build` and Playwright/Vitest checks.
- Commit, verify clean diff against `develop`, and merge into `develop`.

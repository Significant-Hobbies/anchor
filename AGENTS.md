# Anchor — Agent Instructions

<!-- Single source of truth for all AI coding agents. CLAUDE.md symlinks here. -->
<!-- Keep this file short. Detail lives in docs/. -->

## What Anchor is

A focus timer for macOS, iOS and watchOS. You name a goal, run a timer, and when
something distracts you, you park it in one keystroke instead of losing the
session. It then reports what actually costs you your focus. Storage is SwiftData
+ CloudKit; grouping and tagging use Apple's on-device foundation model. Ships
under Significant Hobbies (`com.significanthobbies.anchor`).

## Critical constraints

- **Distraction notes never leave the device.** No cloud model, no analytics SDK,
  no telemetry, no account. Tagging and summarising go through
  `TaggingService`, which uses `FoundationModels` locally or falls back to rules.
  Any change that sends user text off-device is a product violation, not a tradeoff.
- **On-device intelligence is optional, never required.** Apple Intelligence may be
  ineligible, disabled, or still downloading. Every model path must degrade to
  `HeuristicTagger` and the app must stay fully usable. Summaries are omitted
  rather than faked.
- **Timing is derived from the wall clock**, never from a tick count. `TimeAccount`
  is the only place that decides what "elapsed" means. Do not add a counter that
  increments on a timer — it would drift across sleep, relaunch and device sync.
- **Never overwrite a user-set category.** `Distraction.kindIsUserSet` is a lock;
  the tagger must respect it.
- **Resuming always opens the capture sheet**, and declining must stay free
  (`Esc` / "Nothing — just a break"). Prompting on resume is only acceptable
  because saying no costs nothing; do not add friction there, and do not move the
  prompt to `pause()` — the user is already walking away at that point.
- **Nothing that interrupts you may wear the accent colour.** Cobalt is focus;
  distractions are coral / violet / amber by origin. The macOS sidebar selection
  reads `Apps/Shared/Assets.xcassets/AccentColor`, not `.tint()`, so the token and
  the asset must be changed together.
- **The schema must stay CloudKit-compatible**: every attribute has a default or is
  optional, every relationship is optional, and there are no unique constraints.
  Violating this breaks sync silently at runtime, not at compile time.

## Build, test, run

```bash
swift build && swift test          # shared package — 60 tests, no Xcode needed
cd Apps && xcodegen generate       # regenerate the Xcode project after editing project.yml
xcodebuild -project Apps/Anchor.xcodeproj -scheme "Anchor (macOS)" build
xcodebuild -project Apps/Anchor.xcodeproj -scheme "Anchor (iOS)" \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Apps/Anchor.xcodeproj -scheme "Anchor (watchOS)" \
  -destination 'generic/platform=watchOS Simulator' build
```

**Three configurations.** `Debug`/`Release` sign against team `8F7LXHTJZR` with
the CloudKit and app-group entitlements — that is the shipping configuration and
must stay the default. `DebugLocal` drops entitlements and signing so the apps
build on a machine that isn't registered in the developer account; CloudKit is
simply off there. Never "fix" a signing error by weakening `Debug`.

`Apps/Anchor.xcodeproj` is **generated** — edit `Apps/project.yml`, never the
`.xcodeproj`, and never commit build output.

Verify on-device tagging actually works before trusting it:

```bash
./.build/debug/anchor-mcp --diagnose   # expects 8/8 distractions, 4/4 goals
```

Screenshots and manual QA: `ANCHOR_DEMO_DATA=1` seeds three weeks of history into
an empty store, and `ANCHOR_INITIAL_TAB=insights` opens on a given tab. Both are
ignored outside demo mode. `ANCHOR_STORE_PATH` redirects the database, which is how
to avoid touching real data while testing.

## Where things live

| Area | File |
| --- | --- |
| Timing model (pure, exhaustively tested) | `Sources/AnchorCore/Session/TimeAccount.swift` |
| Session state machine | `Sources/AnchorCore/Session/FocusController.swift` |
| SwiftData models | `Sources/AnchorCore/Models/` |
| Store location and resilience | `Sources/AnchorCore/Store/AnchorStore.swift` |
| On-device tagging + prompts | `Sources/AnchorCore/Intelligence/TaggingService.swift` |
| Rule-based fallback | `Sources/AnchorCore/Intelligence/HeuristicTagger.swift` |
| All reported numbers | `Sources/AnchorCore/Analytics/AnalyticsEngine.swift` |
| Hand-written xlsx and zip | `Sources/AnchorCore/Export/` |
| Design tokens | `Sources/AnchorUI/Design/AnchorTheme.swift` |
| MCP server | `Sources/anchor-mcp/main.swift` |
| Watch views | `Sources/AnchorUI/Watch/WatchRootView.swift` |
| Signing, entitlements, targets | `Apps/project.yml` + `Apps/*/Anchor.entitlements` |
| Landing / support / privacy | `landing/` (Astro, static) |

## Conventions

- Analytics, export and MCP read `SessionRecord`/`DistractionRecord` snapshots, not
  SwiftData objects. Keep new query logic pure and testable the same way.
- One accent colour, one card, one spring. Reach for `AnchorTheme`, `Space`,
  `Radius` and `Motion` rather than literals.
- Prompt changes to `TaggingService` must be re-verified with `--diagnose`. The
  on-device model is small; it needed worked examples and the rule matcher's
  suggestion as a hint before it stopped reading "Slack from Ravi" as a physical
  interruption.
- Platform differences between Mac and iPhone belong behind `#if os(...)` in
  `AnchorUI`, not in duplicated screens. Those two apps are shells.
- **watchOS is the exception.** The Mac/iPhone screens are wrapped in
  `#if !os(watchOS)` because the watch has no file exporter, pasteboard or
  keyboard shortcuts, and the watch has its own views in `AnchorUI/Watch/`. Only
  the design system and `FocusRing` are shared with it. Keep it that way rather
  than threading size guards through the big screens.
- The watch is a **remote**, not a small copy: it starts, pauses, resumes and
  captures, and never shows analytics.

## Documentation

- [`docs/architecture.md`](docs/architecture.md) — structure and the reasoning behind it
- [`docs/mcp-and-export.md`](docs/mcp-and-export.md) — MCP tools and export formats
- [`docs/decisions.md`](docs/decisions.md) — decision log

## Work queue

GitHub Issues. An open issue is a to-do; an open issue with a PR is in progress; a
merged PR plus a closed issue is done.

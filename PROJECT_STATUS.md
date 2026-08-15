# Anchor — Project Status

## Why / What

A focus timer that treats distractions as the main event rather than an
afterthought. You name a goal and start a timer; when something pulls at you, one
keystroke parks it and hands you back your goal and your remaining time. Anchor
then reports what actually costs you your focus — and, crucially, whether the pull
came from the world or from you.

macOS and iOS from one shared Swift package. Local-first: distraction notes never
leave the device, and grouping and tagging run against Apple's on-device model.

## Dependencies

Zero third-party packages. Everything is Apple platform frameworks:

- **SwiftData + CloudKit** — storage and private sync
- **FoundationModels** — on-device tagging, grouping and summaries (optional; falls
  back to built-in rules)
- **SwiftUI + Swift Charts** — both apps and all analytics
- **XcodeGen** — generates `Apps/Anchor.xcodeproj` from `Apps/project.yml`

Requires macOS 26 / iOS 26 and Xcode 27.

## Timeline

- **2026-08-16** — Built. Shared package (`AnchorCore`, `AnchorUI`, `anchor-mcp`),
  both app targets, 60 tests, on-device tagging verified 12/12, both apps run and
  screenshotted.

## Products

| Surface | State |
| --- | --- |
| Anchor for macOS | Builds and runs; main window, menu-bar panel, floating mini timer |
| Anchor for iOS | Builds and runs in simulator; full app |
| `anchor-mcp` | Working stdio MCP server, 7 tools, verified against a live store |

Not deployed — these are local Apple apps, not a web surface. No signing team is
configured, so builds are ad-hoc signed for local use.

## Features (shipped)

- Focus sessions against a goal, with wall-clock timing that survives relaunch,
  sleep and cross-device sync
- Pause, resume, extend at the bell, and honest end-reason recording
  (completed / ended early / abandoned)
- Distraction capture (`⌘⇧L`) with a park-and-return confirmation, plus an explicit
  "it wins" path that records the loss
- Resuming a paused session asks what pulled you away, with a free "just a break"
  decline — turns the ordinary pause habit into data
- Compact version in the menu bar and as a floating mini timer (`⌘0`): start,
  pause, resume, capture and end without the main window
- Parked-item list with follow-up tracking and category correction
- On-device tagging of goals into themes and distractions into 14 categories, with
  a deterministic rule-based fallback
- Analytics: focus by day, distraction leaderboard, internal/external origin split,
  focus by hour, per-goal breakdown, streaks, and an on-device written summary
- Export to `.xlsx` (hand-written writer, no dependencies), CSV and JSON
- MCP server with diagnostics mode
- macOS menu-bar extra: live countdown, quick park, pause/end

## Work queue

GitHub Issues. Not yet created — the repository has no remote.

Known gaps carried forward: CloudKit sync unverified against a real account, no
Apple Watch target (`SystemLanguageModel` is unavailable on watchOS), and no
signing team configured. See [`docs/decisions.md`](docs/decisions.md#known-gaps).

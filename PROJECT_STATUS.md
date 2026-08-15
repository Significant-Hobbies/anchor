# Anchor — Project Status

## Why / What

A focus timer that treats distractions as the main event rather than an
afterthought. You name a goal and start a timer; when something pulls at you, one
keystroke parks it and hands you back your goal and your remaining time. Anchor
then reports what actually costs you your focus — and, crucially, whether the pull
came from the world or from you.

macOS, iOS and Apple Watch from one shared Swift package, shipping under
Significant Hobbies. Local-first: distraction notes never leave the device,
grouping and tagging run against Apple's on-device model, and sync goes through
the user's own private CloudKit database.

## Dependencies

Zero third-party packages. Everything is Apple platform frameworks:

- **SwiftData + CloudKit** — storage and private sync
- **FoundationModels** — on-device tagging, grouping and summaries (optional; falls
  back to built-in rules)
- **SwiftUI + Swift Charts** — both apps and all analytics
- **XcodeGen** — generates `Apps/Anchor.xcodeproj` from `Apps/project.yml`

Requires macOS 26 / iOS 26 / watchOS 26 and Xcode 27. Team `8F7LXHTJZR`.

## Timeline

- **2026-08-16** — Built. Shared package (`AnchorCore`, `AnchorUI`, `anchor-mcp`),
  both app targets, 77 tests, on-device tagging verified 12/12, both apps run and
  screenshotted.
- **2026-08-16** — Landing, support and privacy pages live at
  `anchor.significanthobbies.com` (Cloudflare Pages `anchor-landing`, custom
  domain attached with a Google Trust Services certificate).
- **2026-08-16** — Developer ID signed, hardened-runtime `Anchor-1.0.dmg` built
  by `scripts/release-mac.sh`. Notarisation still needs an app-specific password.
- **2026-08-16** — Moved under Significant Hobbies. CloudKit + app-group
  entitlements wired against team `8F7LXHTJZR`, Apple Watch target added and run
  in the simulator against a store written by the Mac, and Astro landing/support/
  privacy pages built for App Store Connect.

## Products

| Surface | State |
| --- | --- |
| Anchor for macOS | Builds and runs; main window, menu-bar panel, floating mini timer |
| Anchor for iOS | Builds and runs in simulator; full app, embeds the watch app |
| Anchor for watchOS | Builds and runs in simulator; remote for start/pause/capture |
| `anchor-mcp` | Working stdio MCP server, 7 tools, verified against a live store |
| Landing pages | **Live** at `anchor.significanthobbies.com` (Pages project `anchor-landing`) |
| macOS DMG | **Signed** Developer ID build, hardened runtime, in `dist/` — not notarised |

Bundle IDs are `com.significanthobbies.anchor(.watchkitapp)`, signed against team
`8F7LXHTJZR`. **iOS and watchOS produce signed device builds** against an
Apple-issued provisioning profile that carries the iCloud container and app
group. **macOS signed builds are blocked on registering this Mac in the developer
account** — use the `DebugLocal` configuration until then.

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
- Apple Watch app: session ring, start from a recent goal with the Digital Crown,
  pause/resume, and one-tap distraction capture
- CloudKit sync via a shared app group and private iCloud database
- Landing, support and privacy pages for App Store Connect
- App icon for all three platforms, drawn from the app's own ring mark

## Work queue

GitHub Issues. Not yet created — the repository has no remote.

Known gaps carried forward:

- **macOS signed builds blocked**: this Mac is not registered in the developer
  account. One interactive step in Xcode unblocks it.
- **CloudKit sync unverified end-to-end**: the entitlements are confirmed
  embedded in a signed iOS device build (`iCloud.com.significanthobbies.anchor`,
  CloudKit service, `group.com.significanthobbies.anchor`, team `8F7LXHTJZR`),
  but two devices syncing to each other has not been exercised.
- **DMG is signed but not notarised**: Gatekeeper will warn on other Macs until
  it is. Needs an app-specific password from appleid.apple.com stored via
  `xcrun notarytool store-credentials`, then re-run the release script with
  `ANCHOR_NOTARY_PROFILE` set.
- **The direct-download build has no iCloud sync** — see the release notes in
  `scripts/release-mac.sh`. The App Store build keeps CloudKit.
See [`docs/decisions.md`](docs/decisions.md#known-gaps).

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
the user's own private CloudKit database. Optional Personal Platform sync sends
session timing and interruption counts, never distraction text.

## Dependencies

No third-party runtime packages. The app uses Apple platform frameworks plus
the first-party PersonalSyncKit package:

- **SwiftData + CloudKit** — storage and private sync
- **FoundationModels** — on-device tagging, grouping and summaries (optional; falls
  back to built-in rules)
- **SwiftUI + Swift Charts** — both apps and all analytics
- **XcodeGen** — generates `Apps/Anchor.xcodeproj` from `Apps/project.yml`
- **PersonalSyncKit** — optional Better Auth connection plus a durable
  Cloudflare session-summary outbox; distraction notes are excluded by contract

Requires macOS 26 / iOS 26 / watchOS 26 and Xcode 27. Team `8F7LXHTJZR`.

## Timeline

- **2026-08-23** — prepared iOS build `1.0 (5)` with a local ActivityKit Live
  Activity for the Lock Screen and Dynamic Island. It mirrors the active focus
  intention, wall-clock remaining or elapsed time, pause state, and parked
  interruption count; relaunch reconciliation reuses the matching system
  activity and cleans up stale ones. The primary iPhone start action now sits
  in a safe-area inset above the floating tab bar. The slice passes 111 shared
  tests, the tab-bar-clearance UI journey, Xcode 26.6 iPhone builds, and Xcode
  27 Mac/watch builds. Physical iPhone verification covered start, Dynamic
  Island presentation, deep-link return, pause/resume, matching frozen time,
  and end. The personal-team App Store archive was accepted by App Store
  Connect and is processing as `1.0 (5)`; internal TestFlight assignment remains.

- **2026-08-23** — Removed the `site/` landing fork. Its `wrangler.toml`
  declared `name = "anchor-landing"` — the Cloudflare Pages project the shared
  `ios-landings` factory owns and deploys — so a deploy from this repo would
  have replaced the live factory site. Live HTML is byte-identical to the
  factory build; the fork differed by 6 lines of inlined CSS reset, i.e. a
  stale copy of the same engine. This is the second such tree retired from
  this repo after `landing/`; the factory is now the only landing source.

- **2026-08-22** — added an interruption-first Mac/iPhone onboarding: an
  explicitly ephemeral park-and-return rehearsal, platform-specific capture
  guidance, real-session handoff through `FocusController`, existing-session
  precedence, existing-owner orientation, Reduce Motion, and privacy education.
  The rehearsal has no SwiftData or sync representation, so practice notes
  cannot enter history, exports, CloudKit, or Personal Platform.

- **2026-08-22** — Apple completed processing Anchor for iOS 1.0 (2) from an
  Xcode 27 Beta 5 personal-team archive. The signed IPA retains CloudKit and the
  shared app group and embeds the Watch app. The valid build is assigned to the
  owner in the internal `Personal Testing` group with automatic distribution.
- **2026-08-22** — Installed Anchor 1.0 (2) from merged Personal Platform sync
  revision `5d07e7e19eb23c6a352dbc5e1c4cfb143d497e77` in `/Applications` using Xcode
  27 Beta 5. The Developer ID signature, hardened runtime, version metadata,
  launch, and running process were verified; the previous app remains
  recoverable in Trash.
- **2026-08-21** — Added the first iPhone UI automation target and verified the
  complete existing loop under Xcode 27 Beta 5: start a session, park an
  interruption, return, pause and resume with the free decline path, end, and
  find the persisted item in Parked. The run exposed and fixed a covered-keyboard
  usability problem by adding explicit Done controls to both multiline forms.
  The personal-team archive remains blocked only on authenticating the Apple
  account in this Xcode installation and refreshing the Sign in with Apple
  profile; tracked in GitHub issue #4.
- **2026-08-21** — Installed Anchor 1.0 (2) in `/Applications` from current
  `main` using Xcode 27 Beta 5. The Developer ID signature, hardened runtime,
  89 shared tests, launch, and running process were verified. The direct build
  remains intentionally local/Google-connectable because Apple does not permit
  its CloudKit, app-group, or Sign in with Apple entitlements without a matching
  provisioning profile.
- **2026-08-21** — Prepared and tested Anchor 1.0 (2) for optional Personal Platform sync
  on iPhone and Mac. Finished sessions push goal/timing/outcome/count metadata,
  Pace-created sessions pull into SwiftData, and raw distraction text is covered
  by a focused non-egress test. The existing CloudKit path stays enabled. App
  Store Connect record `6803853891` now exists as “Anchor by Significant
  Hobbies,” and both 1024px app icons have been flattened to remove invalid
  alpha channels. The Xcode 27 Beta 4 personal-team archive and Apple
  Distribution IPA pass local inspection, but Apple rejects Beta 4 as obsolete.
  Beta 5 is installed; its App Store archive now waits for the personal Apple
  account to be added so Xcode can refresh the Sign in with Apple profile.

- **2026-08-16** — Built. Shared package (`AnchorCore`, `AnchorUI`, `anchor-mcp`),
  both app targets, 77 tests, on-device tagging verified 12/12, both apps run and
  screenshotted.
- **2026-08-16** — Landing, support and privacy pages live at
  `anchor.significanthobbies.com` (Cloudflare Pages `anchor-landing`, custom
  domain attached with a Google Trust Services certificate).
- **2026-08-16** — Both release artifacts build reproducibly:
  `scripts/release-mac.sh` produces a Developer ID signed, hardened-runtime
  `Anchor-1.0.dmg`, and `scripts/release-ios.sh` produces an App Store signed
  `Anchor-1.0.ipa` with CloudKit entitlements and the watch app embedded.
  Notarising and uploading need Apple credentials this repo does not carry.
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
| Landing pages | **Live** at `anchor.significanthobbies.com` (Pages project `anchor-landing`), built from the shared `ios-landings` factory |
| macOS DMG | **Signed** Developer ID, hardened runtime — not notarised |
| iOS/watchOS IPA | **Internal TestFlight available** for 1.0 (2); personal-team 1.0 (5), including Watch and Live Activity targets, uploaded and processing |

Bundle IDs are `com.significanthobbies.anchor(.watchkitapp)`, signed against team
`8F7LXHTJZR`. **iOS and watchOS produce signed device builds** against an
Apple-issued provisioning profile that carries the iCloud container and app
group. **macOS signed builds are blocked on registering this Mac in the developer
account** — use the `DebugLocal` configuration until then.

## Features (shipped)

- Focus sessions against a goal, with wall-clock timing that survives relaunch,
  sleep and cross-device sync
- Automated iPhone coverage for the start, interruption, return, pause/resume,
  end, and persisted Parked-item journey, with explicit keyboard dismissal for
  both multiline entry forms
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
- Optional Cloudflare synchronization for finished session summaries, with
  explicit sign-in and no distraction-note egress
- Landing, support and privacy pages for App Store Connect
- App icon for all three platforms, drawn from the app's own ring mark

## Work queue

Open work is tracked in
[GitHub Issues](https://github.com/Significant-Hobbies/anchor/issues).

Known gaps carried forward:

- **macOS App Store distribution remains unverified**: the personal account is
  now authenticated and the Developer ID build is signed, installed, and
  running, but an entitlement-complete Mac App Store archive has not been made.
- **CloudKit sync unverified end-to-end**: the entitlements are confirmed
  embedded in a signed iOS device build (`iCloud.com.significanthobbies.anchor`,
  CloudKit service, `group.com.significanthobbies.anchor`, team `8F7LXHTJZR`),
  but two devices syncing to each other has not been exercised.
- **DMG is signed but not notarised**. The App Store Connect record exists, the
  iOS/watchOS icon validation defects are fixed, and build 1.0 (2) is available
  to the owner through the internal `Personal Testing` group.
- **The direct-download build has no iCloud sync** — see the release notes in
  `scripts/release-mac.sh`. The App Store build keeps CloudKit.
See [`docs/decisions.md`](docs/decisions.md#known-gaps).

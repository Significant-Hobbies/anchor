# Anchor — Project Status

## Why / What

A private day planner and focus timer that treats divergence as the main event.
You schedule work, commitments, recurring routines, rest, and enjoyment; Anchor
turns focus-capable blocks into its wall-clock timer, captures what pulls you
away, and compares the day you planned with the day it observed. It distinguishes
deliberate changes, internal pulls, external interruptions, human needs,
estimation errors, and honestly unknown gaps without an adherence score.

macOS, iOS and Apple Watch from one shared Swift package, shipping under
Significant Hobbies. Local-first: distraction notes never leave the device,
grouping and tagging run against Apple's on-device model, and sync goes through
the user's own private CloudKit database. Optional Significant Hobbies Hub sync
sends only finished-session goal, start and end times, focused duration, outcome,
and interruption count — never distraction text.

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

- **2026-08-28** — Prepared Anchor `1.0 (14)` for the complete Mac accessibility
  and release pass. Seven isolated native macOS journeys pass together across
  Focus, Today scheduling and review, usual-week routines, Habits, History and
  exports, Mini Timer, onboarding, and Settings. The run fixed schedule-row
  actions and usual-week Add/Done controls that were not reachable through the
  macOS accessibility tree. All 153 shared tests and the 8/8 distraction plus
  4/4 goal on-device diagnostic remain green. Build 14 has not yet replaced the
  accepted build 13 or the installed Mac build 12.

- **2026-08-25** — Prepared Anchor `1.0 (13)` as the doodle-first product
  overhaul release candidate. Mac and iPhone remain thin shells over the same
  `AnchorUI` product root, with the same four surfaces, onboarding, Settings,
  appearance preference, tactile controls, and Significant Hobbies Hub account
  panel. Release verification passes all 153 shared tests, the design-review
  contract, all four iPhone UI journeys on a fresh iPhone 17 Pro simulator, and
  the release-mode Apple Intelligence diagnostic (8/8 interruption categories
  and 4/4 goal themes). The App Store archive and exported IPA pass Apple
  Distribution inspection with the embedded Watch and Live Activity binaries,
  Production APNs and CloudKit, the shared app group, Sign in with Apple, and
  `get-task-allow=false`. The verified IPA is preserved locally as
  `dist/Anchor-1.0-13.ipa` (SHA-256 `7e770abc7ac1b46ba8b6b3934bb47dc9c281efe353417e80b06f522487f49c3a`).
  App Store Connect delivery `30da6599-484e-40f2-8617-c44948f58a03` completed
  through the API-key CLI path after a stable-Xcode rebuild; Apple reports the
  build as `VALID` and `APP_STORE_ELIGIBLE`. A live App Store Connect API check
  on 2026-08-28 confirmed build 13 is assigned to the internal `Personal
  Testing` group. Physical-iPhone installation and the signed Mac-to-iPhone
  acceptance journey remain open. On 2026-08-28 the reachable
  physical iPhone was confirmed to have Anchor 1.0 (11), while the exact current
  source built successfully as development-signed 1.0 (13), including the Watch
  companion, for that device. The development build is not substituted for the
  accepted TestFlight artifact. On macOS, all 153 shared tests, the 8/8 + 4/4
  on-device diagnostic, and seven isolated native UI journeys now pass. The
  native suite covers Focus persistence; one-off scheduling, untimed completion,
  day review, and relaunch; usual-week routines and behavior habits; seeded
  History, interruptions, Trends, and every export entry point; Mini Timer;
  onboarding; and Settings. The expanded run exposed and fixed two Mac
  accessibility gaps: schedule-row actions and the usual-week Add/Done controls
  were not reachable through the accessibility tree. A fresh stable-Xcode
  `ReleaseDirect` archive of build 13 verifies as a universal Developer ID app
  with hardened runtime, Production CloudKit/APNs, the shared app group, and no
  debug entitlement. It was not installed, packaged, notarized, or published;
  `/Applications/Anchor.app` remains build 12.

- **2026-08-24** — Released the unified four-surface source as Anchor `1.0
  (12)`. The Apple Distribution iPhone archive, embedded Watch app, Production
  CloudKit, shared app group, and non-debug entitlements were verified; App
  Store Connect accepted delivery `50f8d0a9-d1c5-4e94-8c49-8979854a8092`
  and began processing it. The matching Developer ID macOS build is installed
  and running from `/Applications`; build 11 is recoverable in Trash. The DMG
  is signed and hardened but not notarized because the local notary credential
  profile is not installed.

- **2026-08-24** — Reshaped Anchor around the final four-surface loop in issue
  #34: Focus resolves the current/next scheduled block and records explicit
  actual-activity overrides; Today shows the full chronological schedule and a
  neutral completion percentage; Habits owns behavior patterns, concrete
  replacements, and recurring templates; History owns selectable planned-versus-
  actual review with interruptions and trends behind it. Onboarding now carries
  the original Indulge artwork through replacement selection, editable weekly
  scheduling, and the interruption rehearsal. Settings moved behind the gear.
  Verification on the final source: 134 shared tests across 19 suites, DebugLocal
  macOS/iOS Simulator/watchOS Simulator builds, both Mac UI journeys, all four
  focused iPhone UI journeys, and the live Apple Intelligence diagnostic (8/8
  interruption categories and 4/4 goal themes).

- **2026-08-24** — Removed the inherited date browser from Today before build
  12: Today is permanently the current day, History owns past-day selection,
  and Habits owns recurring future scheduling.

- **2026-08-24** — Merged Indulge's planning and pattern-change loop into Anchor
  locally under issue #33. Anchor now has a Day plan/review surface, recurring
  schedule templates, plan-to-session links, explicit divergence evidence, an
  editable private behavior profile, and Indulge's original onboarding,
  activity, and life-direction artwork with provenance. Export and MCP include
  plan/review data. The consolidation was committed to Anchor as `c842c8c`;
  no production-store migration was performed.

- **2026-08-24** — Declared Anchor the sole maintained successor to
  Indulge/Habits. The original hero, 24 behavior illustrations, eight life
  directions, and non-moralizing replacement framing are now locally owned by
  Anchor with self-contained provenance. The separate Life/Trade/History shell,
  long identity questionnaire, scene-room system, and duplicate Focus journal
  are intentionally retired. Existing bundle IDs, stores, provider resources,
  and Hub `habits` contracts remain compatibility data; no deletion or data
  migration was performed.

- **2026-08-23** — Anchor `1.0 (10)` completed App Store Connect processing and
  entered internal beta testing (delivery UUID
  `1c00ceed-b69e-4db1-955c-b8592f83ac32`). The build is installed on the
  connected iPhone and includes the embedded Watch app and Live Activity. The
  matching Developer ID build is installed and running in `/Applications` on
  the Mac, with build 9 retained recoverably in Trash. Apple Distribution and
  Developer ID signing, hardened runtime, production iCloud, the shared app
  group, and `get-task-allow=false` were verified. Paired-watch interaction
  remains tracked separately in issue #10 because Watch Developer Mode is
  disabled.

- **2026-08-23** — Separated customer-facing sync truth into two clear paths:
  iCloud continuity for full Anchor data across Apple devices, and optional
  Significant Hobbies Hub visibility for finished-session summaries. Settings
  now show active syncing, the durable outbox count, last successful Hub sync,
  and persistent expired-sign-in, offline, or service failure states. The exact
  Hub payload is contract-tested to exclude both distraction notes and session
  notes. All 118 shared tests pass, along with iPhone and Watch simulator builds
  and a local-only Mac build; the default Mac development build still requires
  the repository's unavailable App Development provisioning profile.

- **2026-08-23** — Anchor `1.0 (8)` was accepted by App Store Connect and is
  assigned to the internal `Personal Testing` group. Its iPhone and embedded
  Watch binaries carry Production APNs, Production CloudKit, and the shared app
  group. The matching Developer ID Mac build is installed in `/Applications`.
  Production CloudKit now contains all six Anchor record types. Build 8 registers
  every native client for remote notifications after launch and explicitly
  reconciles the active controller after remote-store imports. The release passes
  all 114 shared tests. Final build-8 phone installation and Watch interaction
  remain physical-device acceptance steps; the connected phone still has build 7.

- **2026-08-23** — Anchor `1.0 (6)` is assigned in internal TestFlight and
  installed on the physical iPhone; its embedded Watch companion is installed
  and enabled on the paired Apple Watch. The matching Developer ID Mac build is
  installed in `/Applications`, with build 3 retained recoverably in Trash.
  Physical checks confirmed the compact iPhone start action clears the tab bar
  and the local ActivityKit timer appears outside the app. A fresh Mac timer did
  not reach iPhone, and a fresh iPhone timer did not reach Mac. CloudKit Console
  confirms why: Production still contains only `Users`; the pending Development
  schema has timer types but must be expanded to all six Anchor model types and
  reviewed before deployment. The release passes 114 shared tests plus signed
  Mac, iPhone, and Watch builds.

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
| Anchor for macOS | **Installed and running as 1.0 (12)**; current 1.0 (14) source passes the complete Mac QA suite, but has not replaced the installed app |
| Anchor for iOS | **App Store Connect 1.0 (13) is VALID, APP_STORE_ELIGIBLE, and assigned to Personal Testing**; the reachable physical iPhone still has 1.0 (11), so the TestFlight upgrade remains pending |
| Anchor for watchOS | Embedded in accepted build 1.0 (13) with Production CloudKit and APNs; the paired physical Watch is available but direct developer inspection is blocked because Developer Mode is disabled |
| `anchor-mcp` | Working repo-built stdio MCP server, 10 tools; not bundled or advertised by the signed Mac app until protected-store access has an app-mediated design |
| Landing pages | **Live** at `anchor.significanthobbies.com` (Pages project `anchor-landing`), built from the shared `ios-landings` factory |
| macOS DMG | **Build 12 signed** Developer ID, hardened runtime — not notarised |
| iOS/watchOS IPA | **App Store Connect accepted and internally assigned 1.0 (13)**, including Watch and Live Activity targets; physical acceptance pending |

Bundle IDs are `com.significanthobbies.anchor(.watchkitapp)`, signed against team
`8F7LXHTJZR`. **iOS and watchOS produce signed device builds** against an
Apple-issued provisioning profile that carries the iCloud container and app
group. The installed macOS Developer ID build carries the same Production
CloudKit container and app group.

## Features (current source)

- Local day planning with one-off blocks and recurring weekly routines for work,
  commitments, rest, and intentional enjoyment
- Evidence-first daily review of planned versus observed time, with deliberate
  replans, internal pulls, external interruptions, human needs, estimation
  errors, and Unknown kept distinct — never collapsed into an adherence score
- Six-stage private onboarding using Anchor's doodle language: automatic
  patterns, desired directions, concrete replacement habits, editable weekly
  scheduling, an optional Significant Hobbies Hub account, and an interruption
  rehearsal
- Four primary pages only: schedule-led Focus, Today, Habits, and History;
  Settings is available from the gear action
- Focus sessions against the current/next schedule block, with an explicit
  actual-activity override and wall-clock timing that survives relaunch, sleep,
  and cross-device sync
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
- Parked-item list with follow-up tracking and category correction inside History
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
- Optional Significant Hobbies Hub visibility for finished session summaries,
  with explicit sign-in, durable pending/last-success/failure status, and no
  distraction-note egress
- Landing, support and privacy pages for App Store Connect
- App icon for all three platforms, drawn from the app's own ring mark

## Work queue

Open work is tracked in
[GitHub Issues](https://github.com/Significant-Hobbies/anchor/issues).

Known gaps carried forward:

- **Final build-13 physical acceptance remains pending**: Apple has accepted the
  Production-entitled IPA as `VALID` and `APP_STORE_ELIGIBLE`, but the reachable
  physical iPhone still has build 11. Install build 13 from the confirmed
  `Personal Testing` assignment, then run the last open-app Mac–iPhone
  plan/focus/pause/end round trip without exposing distraction text.
- **Physical Watch interaction remains pending**: the paired Watch is available,
  but watchOS Developer Mode is disabled. Install the accepted embedded companion
  through TestFlight before the final remote-control verification.
- **macOS App Store distribution remains unverified**: the Developer ID build is
  signed, installed, and running, but an entitlement-complete Mac App Store
  archive has not been made.
- **The current-source macOS DMG is not built or notarised**. The installed and
  preserved DMG is build 12; rebuild build 14 before notarising or publishing it.
- **The MCP helper is developer-only on macOS**. A raw bundled CLI cannot carry
  the app's provisioning profile, and macOS denies it direct access to the
  protected app-group store. Ship an app-mediated bridge before restoring MCP
  setup to Settings.
See [`docs/decisions.md`](docs/decisions.md#known-gaps).

# Anchor

Plan the day, protect the present, and learn what moved it.

Replace unwanted habits with good ones, check them off, and schedule the ones
that need a time. Pick a day, edit or copy its entries, tag them to projects, and
play an entry. When something interrupts you, park it, pause and come back, or
end the session. History keeps the plan and what actually happened visible.

Runs on macOS, iOS and Apple Watch from one shared codebase. The app is local-first;
distraction text always stays on your device.

![Anchor running a focus session](docs/images/session.png)

## What it does

- **Focus** automatically offers the current or next scheduled block, lets you
  name what you are actually doing when reality changes, and keeps interruption
  capture on top of the live wall-clock timer.
- **Today** lets you select, edit, and copy a day's schedule. Copies keep times
  and projects, start unfinished, and preserve existing destination entries.
  Add a spontaneous entry directly; no habit or recurring rule is required.
- **Habits** carries Indulge's original behavioral artwork from automatic-pattern
  selection into concrete replacements. Check a habit off directly, undo it,
  or optionally schedule it. There is no required progression programme.
- **History** compares the planned and lived day, with interruption evidence,
  internal choices, external causes, and Unknown kept distinct. Parked items and
  longer-term analytics live here as secondary views.
- **Capture a distraction** (`⌘⇧L`) — park it and keep working, pause and return
  to the same session, or end the session. Break time does not count as focus.
- **Resuming asks what pulled you away.** A pause is usually an interruption, so
  coming back captures it — with "nothing, just a break" one key away.
- **A compact version** that lives in the menu bar, or as a floating mini timer
  (`⌘0`). Start, pause, resume, capture and end without opening the main window.
- **Apple Watch** as a remote: start, pause, and catch the interruption at the
  moment it happens without picking anything up.
- **Sync** through your own private iCloud database, plus optional Significant
  Hobbies Hub session summaries after you connect and approve local history.
- **On-device tagging** — Apple Intelligence sorts goals into themes and
  distractions into categories, so analytics work without you tagging anything.
- **Analytics** — where your hours and billable value go, what interrupts you,
  project and tag breakdowns, session depth, weekday rhythm, and active time that
  was not covered by a session.
- **Export** — real `.xlsx`, CSV, JSON.
- **MCP server** — point Codex at your focus history and just ask.

Landing, support and privacy pages: <https://anchor.significanthobbies.com> — built and
released from the shared `ios-landings` factory (`products/anchor/`), not from this repo.

## Requirements

macOS 26 / iOS 26 / watchOS 26 or later, Xcode 27. Apple Intelligence is optional:
without it, tagging falls back to built-in rules and the app is otherwise
unchanged. Apple Watch never has it, so anything captured there is refined by the
phone or Mac once it syncs.

## Build and run

```bash
# Shared package: builds and tests from the command line, no Xcode needed
swift build
swift test

# App targets
cd Apps && xcodegen generate && open Anchor.xcodeproj
```

Pick the **Anchor (macOS)**, **Anchor (iOS)** or **Anchor (watchOS)** scheme and run.

CloudKit sync and the shared app group are entitlements, so the default `Debug`
and `Release` configurations sign against the team. If this machine isn't
registered in the developer account yet, build the `DebugLocal` configuration —
it drops entitlements and signing, and the store falls back to local-only:

```bash
xcodebuild -project Apps/Anchor.xcodeproj -scheme "Anchor (macOS)" \
  -configuration DebugLocal build
```

To explore with three weeks of plausible history instead of an empty database:

```bash
ANCHOR_DEMO_DATA=1 ./path/to/Anchor.app/Contents/MacOS/Anchor
```

Set `ANCHOR_INITIAL_TAB` to `focus`, `today`, `habits`, or `history` in demo
mode. The old `day`, `log`, and `insights` values remain accepted as aliases for
repeatable screenshot workflows.

Demo data is only ever written into an empty store.

## Releasing

```bash
./scripts/release-mac.sh    # Developer ID signed, hardened Anchor-<v>.dmg
./scripts/release-ios.sh    # App Store signed Anchor-<v>-<build>.ipa
./scripts/release-ios.sh --upload       # build, verify, and deliver to Apple
./scripts/release-ios.sh --upload-only  # deliver the existing build
```

Both write to `dist/` and verify what they produced — signature, hardened
runtime, entitlements, and (for iOS) that the watch app is really in the payload.

Credentials stay in the macOS login Keychain. Configure or refresh the iOS
upload credential once using a hidden prompt; the password never enters the
repository, command arguments, logs, or shell history:

```bash
./scripts/release-ios.sh --configure-upload

# Notarise the DMG (once: store an app-specific password from appleid.apple.com)
xcrun notarytool store-credentials "anchor-notary" \
  --apple-id "<apple-id>" --team-id 8F7LXHTJZR --password "<app-specific-password>"
ANCHOR_NOTARY_PROFILE=anchor-notary ./scripts/release-mac.sh
```

The Mac direct-download and iOS/watchOS builds use the same production CloudKit
container. Each distribution channel has its own provisioning profile, so the
restricted iCloud and app-group entitlements remain intact.

## Talking to your data

The repository builds an MCP server for developer use, so an AI client can query
your history directly rather than making you export a file first. It is not
currently bundled with the signed Mac app.

```bash
swift build -c release
codex mcp add anchor -- "$PWD/.build/release/anchor-mcp"
```

Then ask things like *"what broke my focus most this month?"* or *"why did today's
plan move?"*. Ten tools; see [`docs/mcp-and-export.md`](docs/mcp-and-export.md).

Check that on-device tagging is working on your machine:

```bash
./.build/release/anchor-mcp --diagnose
```

## Layout

```
Sources/
  AnchorCore/     models, timing, tagging, analytics, export — no UI, fully tested
  AnchorUI/       SwiftUI screens and the design system, shared by both apps
  anchor-mcp/     stdio MCP server over the same store
Apps/
  Mac/ iOS/ Watch/  thin app shells; project.yml generates the Xcode project
  Shared/          asset catalog (accent colour + app icon)
Tests/            shared tests, no Xcode required
```

## Documentation

- [Architecture](docs/architecture.md) — how the pieces fit and why
- [MCP and export](docs/mcp-and-export.md) — tools, formats, the hand-written xlsx writer
- [Indulge/Habits consolidation](docs/INDULGE_RETIREMENT.md) — what Anchor carries,
  what it replaces, and which compatibility resources remain
- [Asset provenance](docs/ASSET_PROVENANCE.md) — self-contained origin records
  for the merged onboarding artwork
- [Decisions](docs/decisions.md) — the calls made along the way, and what they cost

## Privacy

Distraction notes are the most personal thing in the app, so they never leave the
device. Tagging and summarising run against Apple's on-device model. SwiftData
and private CloudKit remain local-first storage. If you explicitly connect
Significant Hobbies, Anchor also sends only the goal, start and end times,
focused duration, outcome, and interruption count to your private Significant
Hobbies Hub. There is no analytics SDK.

<!-- portfolio-retained-work:2026-09-07 -->
## Retained work from the portfolio review

These are unresolved requirements retained at the owner’s request. They are not completed features. Work should follow a concrete need and fresh evidence.

### Qualify the simpler daily loop on the owner's devices

Direct habit tracking, daily editing/copying, project-linked entries and pause
recovery are implemented. The development iPhone build is installed; physical
use, Production CloudKit promotion and the notarized Mac release remain open.
See [the qualification receipt](docs/qualification/simple-day-2026-09-07/README.md)
and [#51](https://github.com/Significant-Hobbies/anchor/issues/51).

### Sync with Apple Reminders

Design and verify bounded Apple Reminders synchronization without losing either application’s original records.

Original requirements and discussion: [#50](https://github.com/Significant-Hobbies/anchor/issues/50).

### Ship a signed app-mediated MCP bridge for macOS

Qualify the signed, app-mediated MCP bridge with explicit access boundaries and installed-app evidence.

Original requirements and discussion: [#41](https://github.com/Significant-Hobbies/anchor/issues/41).

### Verify signed Hub authentication and clean account provenance

Account-scoped queues, fingerprints, versions, cursors and receipts now have
[headless transport proof](docs/hub-account-qualification-2026-09-07.md), including
account switching, failed retries and delayed responses. Legacy unscoped state
is retained without assigning it to an identity. Signed Apple/Google sign-in,
provider recovery and installed-app local/iCloud continuity remain unverified;
these source checks do not close the acceptance task.

Build 24 adds explicit history approval, device-local ownership, and session
ownership that travels with iCloud records. Signing into another Hub account
cannot automatically re-export the same local history. Finish active focus
before approval; new phone/Mac sessions inherit the approved owner offline.
The approval control is in the existing Hub panel. A failed approval or account
switch preserves local history and pending changes.

This change adds optional `FocusSession.hubAccountID` to the SwiftData schema.
Production CloudKit support for that field and real two-device ownership
continuity must be verified before claiming this build's sync is ready. Package
and synthetic transport tests do not establish that provider compatibility.

Original requirements and discussion: [#40](https://github.com/Significant-Hobbies/anchor/issues/40).

### Device-only distraction-note migration

Source migration work and failure/restart evidence are tracked in [#52](https://github.com/Significant-Hobbies/anchor/issues/52) and [the qualification receipt](docs/qualification/private-notes-2026-09-09/README.md). Existing installed builds can still store distraction notes in private CloudKit. Historical cloud copies, mixed-version provider behavior and signed-device qualification remain release gates; local/package checks alone do not qualify owner-data rollout.

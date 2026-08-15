# Anchor

A focus timer that takes distractions seriously.

You set an anchor — the thing you're actually trying to do — and start a timer.
When something pulls at you, one keystroke parks it: you name it in a sentence,
it's filed, and you're handed back your goal and the time remaining. Afterwards
Anchor tells you what actually costs you your focus.

Runs on macOS and iOS from one shared codebase. Everything stays on your device.

![Anchor running a focus session](docs/images/session.png)

## What it does

- **Focus timer** with a goal, wall-clock accurate across relaunch, sleep and sync.
- **Lock a distraction** (`⌘⇧L`) — name it, park it, keep working. Or record
  honestly that it won.
- **Resuming asks what pulled you away.** A pause is usually an interruption, so
  coming back captures it — with "nothing, just a break" one key away.
- **A compact version** that lives in the menu bar, or as a floating mini timer
  (`⌘0`). Start, pause, resume, capture and end without opening the main window.
- **On-device tagging** — Apple Intelligence sorts goals into themes and
  distractions into categories, so analytics work without you tagging anything.
- **Analytics** — where your hours go, what interrupts you, whether the pull came
  from the world or from you, when you're actually good at this.
- **Export** — real `.xlsx`, CSV, JSON.
- **MCP server** — point Claude at your focus history and just ask.

## Requirements

macOS 26 / iOS 26 or later, Xcode 27. Apple Intelligence is optional: without it,
tagging falls back to built-in rules and the app is otherwise unchanged.

## Build and run

```bash
# Shared package: builds and tests from the command line, no Xcode needed
swift build
swift test

# App targets
cd Apps && xcodegen generate && open Anchor.xcodeproj
```

Pick the **Anchor (macOS)** or **Anchor (iOS)** scheme and run.

To explore with three weeks of plausible history instead of an empty database:

```bash
ANCHOR_DEMO_DATA=1 ./path/to/Anchor.app/Contents/MacOS/Anchor
```

Demo data is only ever written into an empty store.

## Talking to your data

Anchor ships an MCP server, so an AI client can query your history directly
rather than making you export a file first.

```bash
swift build -c release
claude mcp add anchor -- "$PWD/.build/release/anchor-mcp"
```

Then ask things like *"what broke my focus most this month?"* or *"which goal do I
protect best?"*. Seven read-only tools; see [`docs/mcp-and-export.md`](docs/mcp-and-export.md).

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
  Mac/  iOS/      thin app shells; project.yml generates the Xcode project
Tests/            60 tests, no Xcode required
```

## Documentation

- [Architecture](docs/architecture.md) — how the pieces fit and why
- [MCP and export](docs/mcp-and-export.md) — tools, formats, the hand-written xlsx writer
- [Decisions](docs/decisions.md) — the calls made along the way, and what they cost

## Privacy

Distraction notes are the most personal thing in the app, so they never leave the
device. Tagging and summarising run against Apple's on-device model. Sync, when
enabled, is your own private CloudKit database. There is no analytics SDK, no
account, and no server.

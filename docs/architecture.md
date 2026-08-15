# Architecture

Four layers, each of which can be reasoned about without the one above it.

```
Apps/Mac  Apps/iOS        thin shells: scenes, menu bar, commands
      └── AnchorUI        SwiftUI screens + design system
            └── AnchorCore    models, timing, tagging, analytics, export
                  └── SwiftData + CloudKit
anchor-mcp ───────┘        reads AnchorCore directly, no UI
```

`AnchorCore` has no UI import, so `swift test` covers the entire domain from the
command line with no simulator and no Xcode. `AnchorUI` holds every screen, and
the two app targets are shells — this is what keeps the platforms honestly
identical rather than two apps that drift.

## Timing: a bank, not a countdown

[`TimeAccount`](../Sources/AnchorCore/Session/TimeAccount.swift) is the whole
timing model, as a value type. A session is:

- `bankedSeconds` — active time earned before the current run
- `runningSince` — when the currently open interval started, or `nil` if paused

Elapsed time is always `banked + (now - runningSince)`. Nothing increments.

That one choice is what makes the timer correct when the app is quit for an hour,
when the Mac sleeps mid-session, and when the same session is picked up on a
phone. A tick counter would silently under-report in all three cases. It also
means the app has no work to do in the background at all.

The consequences are tested directly: relaunch, pause exclusion, idempotent
transitions, and a backwards clock (NTP corrections are real, and without a guard
the ring would jump backwards).

`FocusController` is the only thing allowed to mutate a session. It owns the one
active session, restores an in-flight one on launch, and drives a cooperative
tick loop that cancels itself when the controller goes away.

## Storage

SwiftData, with CloudKit sync when entitlements allow it. The schema is
CloudKit-shaped by construction — defaults everywhere, optional relationships, no
unique constraints — because CloudKit violations fail at runtime, not compile time.

`AnchorStore.makeResilientContainer()` tries CloudKit, then local-only, then
memory. Losing sync should never mean losing the ability to start a timer.

Store location resolves through `ANCHOR_STORE_PATH`, then the app-group container
*if it already exists*, then Application Support. The existence check matters:
`containerURL(_:)` returns a path whether or not the entitlement was granted, so
it is the only thing that distinguishes a provisioned app from an unsigned CLI.
Both the app and the MCP server run this same logic, so they agree in both worlds.

## Snapshots

Analytics, export and MCP never touch SwiftData objects. They read
`SessionRecord` / `DistractionRecord` — plain `Codable` value types produced by
`snapshot()`.

This buys three things: `AnalyticsEngine` is pure and trivially testable, the MCP
server runs in a plain CLI process without dragging the main-actor world along,
and the export formats cannot drift from what the UI shows because they share one
source.

## On-device intelligence

[`TaggingService`](../Sources/AnchorCore/Intelligence/TaggingService.swift) wraps
`FoundationModels`. `@Generable` structs with `@Guide(.anyOf(...))` constrain the
model to the exact category enums, so an unparseable answer is impossible rather
than merely unlikely.

Every path has a deterministic fallback in `HeuristicTagger`. This is not
defensive padding — Apple Intelligence is genuinely unavailable on ineligible
devices, when the user turns it off, and while assets download. The fallback is
also what the tests assert against, since a language model is not a stable thing
to write assertions about.

Two things had to be true before the model was actually useful:

1. **Worked examples in the instructions.** Without them the model read "Slack
   from Ravi about the invoice" as a physical interruption.
2. **The rule matcher's answer passed in as a hint** the model may override. On
   explicit cues the keyword matcher is reliably right; the model is better at
   everything ambiguous. Together they score 12/12 on `--diagnose`, where the
   model alone scored 10/12.

Summaries are grounded by construction: `AnalyticsEngine.brief` hands over
pre-computed numbers and the instructions forbid inventing any, so the model can
only rephrase. When it is unavailable the summary is omitted rather than replaced
with something worse.

## Design system

One accent colour, one card, one spring — in
[`AnchorTheme`](../Sources/AnchorUI/Design/AnchorTheme.swift). Tokens are resolved
from the colour scheme in code rather than from an asset catalogue, which keeps
the package resource-free and the values greppable.

The palette is built on one rule: **cobalt is focus, warm is interruption.** The
ring, progress and every primary action are cobalt; nothing that breaks a session
is ever allowed to wear that colour. Distraction colour then encodes *origin* —
coral for "the world came to you", violet for "you went to it", amber for mixed.
That split is the most actionable thing in the data, so the eye gets it for free.

One thing does need an asset: macOS draws sidebar selection with the
*asset-catalog* accent colour, and `.tint()` cannot override it. `Apps/Shared/
Assets.xcassets` carries an `AccentColor` matching the token so the system
chrome and the app agree. (Adding that catalog is also why an `AppIcon` set has
to exist — iOS refuses to build a catalog without one.)

Charts that mix units — hours against interruption counts — plot both on one
scale, because Swift Charts has a single y-axis. The count series is mapped onto
the hours axis and the trailing axis is labelled with the inverse, so the two
shapes stay comparable without either lying about its magnitude.

The focus ring is layered back-to-front — halo, track, minute ticks that dim as
they are consumed, the gradient arc, and a lit head at the leading edge. It
breathes only while running, and not at all under Reduce Motion.

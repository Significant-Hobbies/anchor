# Decision log

Built 2026-08-16. The calls that shaped the app, and what each one cost.

## Soft lock, not real app-blocking

**Decision.** A distraction is captured and parked, and the app pushes you back to
your goal. It does not shield or block apps.

**Why.** Apple's Screen Time API (FamilyControls / ManagedSettings /
DeviceActivity) is **iOS and iPadOS only — there is no macOS equivalent**. Real
blocking would have meant an entitlement request Apple takes weeks to grant on one
platform, and a custom force-quit-and-DNS blocker on the other. That is a different,
much heavier product, and the macOS half would have been permanently fragile.

**Cost.** Anchor cannot stop you. It can only make stopping deliberate and make the
pattern visible afterwards. `didReturnToFocus` records honestly when a distraction
won, because a tool that logs only your wins produces analytics you cannot act on.

**Revisit if** the entitlement is granted — `ShieldProvider` would slot in behind
the existing capture flow on iOS without changing the model.

## Apple Watch deferred

Planned, then dropped from this pass on evidence: `SystemLanguageModel` is marked
`@available(watchOS, unavailable)` in the SDK. A watch app is still worth building
as a remote — start, glance, tap to park — but it cannot carry the intelligence
layer, so it is a genuinely separate design rather than a third target.

## Wall-clock timing instead of a tick counter

Elapsed time is derived from timestamps, never accumulated. This is the decision
the rest of the app leans on: it makes relaunch, sleep and cross-device sync
correct for free, and means there is no background work at all. See
[architecture](architecture.md#timing-a-bank-not-a-countdown).

## Resuming asks what pulled you away

A pause is the honest signal that something interrupted you — more honest than
remembering to press the lock button first. So resuming always opens the capture
sheet: *"Welcome back. What pulled you away?"*, with how long you were gone.

Asked on **resume**, never on pause: when you pause you are already leaving, and a
prompt at that moment is an obstacle between you and the door.

This only works because saying no is free — "Nothing — just a break" and `Esc` both
dismiss without recording. Without that, prompting on every resume would be nagging
rather than capture. The payoff is that analytics reflect the interruptions you
actually had, not only the ones you had the discipline to log.

## The palette took three attempts

Amber first — legible, but it made focus and interruption read as the same thing,
and it edged toward "hazard". Then jade, which was rejected on sight. Settled on
**cobalt**, chosen by the owner from four costed options.

The lasting decision is not the hue but the rule underneath it: cool is focus, warm
is interruption, and nothing that breaks a session may wear the accent colour. That
survives any future repaint. Lesson recorded plainly: colour is taste, so present
options rather than guessing twice.

## A mini timer window as well as the menu bar

The menu-bar panel is the real compact app — start, pause, resume, capture and end
without the main window. It is also unreachable when the menu bar is full and macOS
hides the icon behind the overflow chevron, which is exactly the case on the
owner's machine.

So the same `CompactPanel` is also a small floating window (`⌘0`). One view, two
mounts — no duplicated compact UI to keep in sync.

## Snapshots between storage and everything else

Analytics, export and MCP read plain `Codable` value types, not SwiftData objects.
Costs a mapping layer. Buys a pure, fully-tested analytics engine, an MCP server
that runs in a plain CLI process, and export formats that cannot drift from the UI.

## A hand-written xlsx writer

No third-party dependency for spreadsheets, which meant implementing ZIP and CRC32
(~300 lines). Worth it for a local-first, privacy-shaped app where every dependency
is something to audit. Entries are stored uncompressed — bigger files, much simpler
code. Verified by actually running `unzip -t` in a test.

## The on-device model needed grounding

First run, the model classified "Slack from Ravi about the invoice" as a *physical
interruption* and "Finish the token refresh" as *admin*. Both are the kind of miss
that quietly poisons a month of analytics.

Two changes fixed it: worked examples in the instructions, and passing the keyword
matcher's answer to the model as a hint it may override. The rule matcher is
reliably right on explicit cues; the model is better at everything ambiguous.
Together: 12/12 on `--diagnose`, up from 10/12.

The general lesson: the on-device model is small. Treat it as something to be
constrained and grounded, not asked open questions. Summaries get the same
treatment — they receive pre-computed numbers and are forbidden from inventing any.

## Fallbacks are a feature, not padding

Apple Intelligence is unavailable on ineligible devices, when switched off, and
while assets download. Every model path degrades to rules and the app is otherwise
unchanged. Summaries are omitted rather than faked — an absent sentence is better
than a worse one.

## Deviation from the "no new products" rule

The workspace has a standing rule against scaffolding new products. This was built
on an explicit direct request, which overrides it. Flagged at the time rather than
silently absorbed.

## Known gaps

- **CloudKit sync is unverified.** The schema is CloudKit-shaped and the container
  falls back cleanly, but sync has not been exercised against a real iCloud
  account — that needs a signing team and two devices. Local storage is verified.
- **No Apple Watch target** (see above).
- **The MCP server reads the store directly.** Fine for concurrent reads under
  SQLite WAL, but it means the binary and the app must agree on store location.
  They share `AnchorStore.storeURL()` for exactly this reason.
- **Ad-hoc signing.** `Apps/project.yml` disables code signing so the apps build
  and run locally without a team. Set `DEVELOPMENT_TEAM` and switch
  `CODE_SIGN_STYLE` to `Automatic` to enable iCloud and the app group.

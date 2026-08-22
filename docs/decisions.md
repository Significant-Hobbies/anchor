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

## The watch is a remote, not a small copy

`SystemLanguageModel` is marked `@available(watchOS, unavailable)` in the SDK, so
the watch cannot carry the intelligence layer at all. That settled its shape: it
starts, pauses, resumes and captures, and never shows analytics. Anything it
records is tagged by rules and re-tagged properly by the phone or Mac once the
store syncs.

Two consequences in the code:

- `TaggingService` guards on `canImport(FoundationModels) && !os(watchOS)`, not
  plain `canImport` — the module *does* exist on watchOS, only the model doesn't.
- The Mac/iPhone screens are wrapped in `#if !os(watchOS)` and the watch gets its
  own views. Threading size guards through screens built around a file exporter,
  a pasteboard and keyboard shortcuts would have produced worse code on all three
  platforms.

Capture on the wrist is mostly one tap: the categories *are* the input, and
dictation is offered for when the specific thing matters.

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

## CloudKit is signed, not simulated

Sync is a real private CloudKit database plus a shared app group, which means
entitlements, which means a provisioning profile. `Debug`/`Release` therefore sign
against the fleet team and are the shipping truth.

That would have made the repo unbuildable on any machine not registered in the
developer account, so there is a third configuration, `DebugLocal`, that drops
entitlements and signing entirely. CloudKit is simply off there and the store
falls back to local-only — which the container was already designed to survive.

Verified rather than assumed: a generic iOS **device** build succeeds, and the
embedded entitlements read back as `iCloud.com.significanthobbies.anchor`, the
CloudKit service, `group.com.significanthobbies.anchor` and team `8F7LXHTJZR`,
against an Apple-issued profile. watchOS device builds sign too.

The remaining blocker is genuinely interactive: this Mac is not registered in the
account, so signed macOS builds fail until someone clicks through Xcode once.

One trap worth remembering: on the **simulator** the main `.xcent` is empty and
the real entitlements live in `*-Simulated.xcent`. Reading the wrong one makes it
look like the entitlements never applied.

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

## A landing page sized for App Store Connect

Apple requires a support URL and a privacy policy URL, and takes a marketing URL.
That is the entire brief, so `landing/` is three static Astro pages with one
stylesheet and no framework — no Tailwind, no components library, no analytics
(which would contradict the privacy page).

The privacy policy is short because it is true: no account, no telemetry, no
servers, no third-party SDKs. It says so plainly rather than hedging with the
usual "we may collect" boilerplate.

Live at `anchor.significanthobbies.com` on Cloudflare Pages as `anchor-landing`.
Wrangler 4 has no `pages domain` command, so the custom domain and its CNAME went
in through the API using the same OAuth-token helper the fleet's other Cloudflare
scripts use. One trap worth recording: with
`build.format: 'file'`, `Astro.url.pathname` is `/privacy.html` at build time
while Pages serves `/privacy`, so the first deploy shipped canonical URLs nobody
could visit. The layout now strips `.html` and `index.html` before building the
canonical.

## The direct-download DMG keeps production CloudKit

`scripts/release-mac.sh` produces a Developer ID signed, hardened-runtime DMG.

CloudKit and app groups are restricted entitlements, so the Developer ID build
uses the `Anchor Developer ID` provisioning profile created through App Store
Connect. Its CloudKit environment is Production, matching the iPhone and Watch
TestFlight builds. `ReleaseDirect` stays separate because its signing identity
and Sign in with Apple capabilities still differ from the App Store build.

Two things the script guards, both learned by tripping over them:

- **Archive, never a plain `build`.** A plain build injects
  `com.apple.security.get-task-allow`, and notarisation rejects anything carrying
  it. The first DMG had it; the script now fails loudly if it reappears.
- **Don't pipe `codesign` into `grep -q` under `pipefail`.** `grep -q` exits on
  first match, SIGPIPEs codesign, and the pipeline reads as failed — which is
  exactly how the hardened-runtime check produced a false negative.

## Known gaps

- **CloudKit sync is unverified end-to-end.** Entitlements, container and app
  group are wired, and iOS and watchOS build signed against them. Two-device sync
  has not been exercised — that needs signed builds on real hardware.
- **macOS signed builds are blocked** on registering this Mac in the developer
  account. `DebugLocal` is the workaround until then.
- **The DMG is signed but not notarised.** Gatekeeper warns on other Macs until
  an app-specific password is stored with `xcrun notarytool store-credentials`
  and the release script is re-run with `ANCHOR_NOTARY_PROFILE`.
- **The app icon is generated, not hand-drawn.** `scripts/make-icon.py` renders
  the ring mark; it reads well down to 16px but a designer could do better.
- **The MCP server reads the store directly.** Fine for concurrent reads under
  SQLite WAL, but it means the binary and the app must agree on store location.
  They share `AnchorStore.storeURL()` for exactly this reason.
- **Watch demo data can't be seeded by environment variable.** `SIMCTL_CHILD_*`
  does not reach a watchOS simulator app, so the watch UI was verified by copying
  a store the Mac had written into the simulator's app-group container — which is
  also a fair rehearsal of the real sync path.

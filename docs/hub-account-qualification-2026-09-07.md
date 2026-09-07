# Hub account provenance qualification — 2026-09-07

Tracking: [Anchor #40](https://github.com/Significant-Hobbies/anchor/issues/40).
This is headless source and transport evidence, not signed Apple/Google login,
installed-app, production Hub, CloudKit or release qualification.

## Repair

Anchor previously constructed one `PersonalSyncRuntime` in its support directory.
Its outbox, fingerprints, versions and cursor were shared across sign-ins, while
transport used the current bearer. A failed A queue could therefore be sent as B,
and A's saved fingerprint could suppress B's initial export. The global receipt
could also show A's success under B. The recent web Hub/Live entry change did not
alter Anchor's native identity routes; this was an existing adapter defect.

New runtime files live under `hub-accounts-v1/<SHA256(stable user ID)>/` and
receipts use the same stable identity namespace. Neither email nor bearer token
is a storage key. An attempt verifies its exact token snapshot against the
identity service before opening a namespace, then binds transport to that token.
Generation and identity checks prevent an earlier account's completion from
changing the current account's receipt, pending count or syncing status.
Concurrent attempts for the same account are excluded to protect its file stores.

The four legacy `personal-sync-*.json` files and the old receipt key remain
untouched and unassigned. They are not adopted by the next account. An existing
account can re-export the current local finished summaries using their stable
record IDs; legacy queued records no longer present locally require an explicit
provenance decision before any recovery. No automatic legacy recovery is claimed.

Sign-out immediately clears the displayed connection receipt and invalidates
pending UI callbacks. It prevents subsequent exports. Requests already sent may
finish under their original account, including their original-account file
updates; they cannot switch to the new bearer or update the new account's UI.
Account deletion also verifies the captured identity and cannot sign out a later
account when its response arrives.

Hub remains an outbound summary view. Local and private iCloud planner data are
independent of the Hub identity: connecting B explicitly exports eligible local
finished summaries to B, but never consumes A's queued records. Pulled remote
history is discarded, not inserted into SwiftData. The existing six-field payload
allowlist remains unchanged; notes and other private planner content are excluded.

## Executable evidence

`Tests/AnchorCoreTests/AnchorAccountSyncTests.swift` runs the actual
`AnchorPlatformSync`, `PersonalIdentityClient`, `PersonalSyncRuntime`, on-disk
queue/state serialization and `PersonalSyncClient` HTTP encoding. A `URLProtocol`
fixture serves synthetic responses on unique `.invalid` origins. Each test uses
an in-memory planner, temporary files, isolated UserDefaults and in-memory tokens.
It performs no provider requests or owner Keychain reads and opens no native UI.

Seven tests, including both delayed-success and delayed-failure arguments, prove:

- A success followed by B produces independent initial exports with base version
  zero and cursor zero. Returning as A with a refreshed token and changed email
  retains A's receipt/cursor/fingerprint; an edited summary uses A's version 7,
  not B's version 19.
- A failed queued summary remains A's after B connects. After local removal of
  that summary, B sends only B's current local summary. Relaunching the adapter
  as A retries A's original mutation and idempotency key and clears its queue.
- All four legacy state files remain byte-identical, the unscoped receipt remains
  intact, and their queued summary is never sent under B.
- Delayed A success and failure cannot clear B's in-flight indicator, pending
  count or receipt. A and B requests retain their own bearer snapshots.
- Sign-out prevents later exports, ignores a delayed success receipt, and leaves
  the local planner usable with its records intact.
- Mismatched and expired tokens send no summaries. Deletion verifies its account
  and a delayed A deletion response leaves B signed in with B's receipt.
- Valid remote-only history never increases the local planner record count.
  Every serialized push also checks the exact payload allowlist and absence of
  the synthetic private note.

## Validation and boundary

Final validation uses an isolated source copy with the checked-in PersonalSyncKit
revision `c9abc093c42174c4361774c4ed37ae5c882e276b`. The owning checkout already has
an editable SwiftPM link to the sibling Hub repository; that local setup and the
existing stash are preserved. Initial exploratory tests used that editable link;
the final qualification uses the exact pinned source instead.

- Focused account transport suite: 7 tests passed.
- Full shared Swift package suite after native-review repairs: 182 tests passed, zero failures or skips.
- Shared Swift package build: passed.
- No production dependencies, lockfile revision, authentication providers,
  Keychain service identity, signing settings or production configuration changed.

The repository's only Actions workflow, `Anchor native review`, is
`workflow_dispatch` only. After a read-only effects audit, the owner authorized
its hosted Mac and simulator tests, including starting Google OAuth and cancelling
without credentials. This contacts Live/Google and can create transient OAuth
state; it does not release, deploy, migrate or modify production configuration.
No UI automation runs on the owner's Mac.

The first hosted run,
[34116034709](https://github.com/Significant-Hobbies/anchor/actions/runs/34116034709),
at `fb2e9f4` failed its final gate. Shared package tests and watch build passed;
Mac UI had 13 passes and one failure, and iPhone UI had six passes and one failure.
GitHub's intermediate step `conclusion` reported success because those commands
use `continue-on-error`; the final gate correctly inspected their failed
`outcome`. The Google start/cancel test itself passed. This is cancellation
proof on an unsigned hosted build, not authenticated Apple/Google acceptance.

Concrete repairs from that run:

- The unsigned Mac onboarding test now checks the existing "Connect your Hub
  account" fallback and absence of an Apple button. Signed Apple acceptance
  remains separate; the entitlement requirement is unchanged.
- Capture journey tests wait for the existing two-second confirmation dismissal
  instead of racing a disappearing "Back to work" button. They still assert
  the saved note, resumed focus and persisted history. Product timing is unchanged.
- Heuristics recognize a physical arrival over generic "chat" while explicit
  messaging channels retain priority. Technical token-refresh context applies
  after writing, learning and planning cues. Counterexamples cover both boundaries.
- Diagnostics now fail with a nonzero exit unless all eight distraction and all
  four goal cases pass. The original run printed 7/8 and 3/4 while exiting zero.
  The repaired executable reports 8/8 and 4/4 with `--diagnose --heuristic-only`.
  An isolated negative control with one deliberately wrong expected category
  reported 7/8 and exited 1; the unchanged source was restored and rebuilt.

All 24 catalog PNGs in the first run's manifest were present, decodable,
nonblank and matched their declared dimensions. A contact-sheet review confirmed
populated primary surfaces. These are offscreen macOS renders of shared views at
Mac/phone sizes, using synthetic in-memory data, not real iPhone screenshots.

The workflow, Google cancellation path and final native gate remain intact.
Latest hosted run receipts are tracked on [#40](https://github.com/Significant-Hobbies/anchor/issues/40).

Issue #40 stays open for signed Apple and Google sign-in, recoverable cancellation,
provider errors, fresh/existing account provenance and signed-app sign-out with
local/iCloud continuity. #41 retains the signed app-mediated MCP bridge and #50
retains Apple Reminders sync. No issue meets its full closure criteria here.

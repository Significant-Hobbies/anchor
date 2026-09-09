# Device-only distraction notes — source qualification

Tracking: [#52](https://github.com/Significant-Hobbies/anchor/issues/52), part of daily-use [#51](https://github.com/Significant-Hobbies/anchor/issues/51).

## Problem reproduced

Original source `b75c1c2161752fc531721b69f2ef1a8655787b9a` uses the actual FocusController capture/pause path to save plaintext `Distraction.note` in the same schema configured for private CloudKit. The synthetic legacy fixture was produced by that exact source in a separate local checkout; no owner store or CloudKit connection was used. It contains one synthetic paused session, one private note, and explicit synthetic keywords.

The checked test resource `Tests/AnchorCoreTests/Fixtures/LegacyNotes.store` is a complete SQLite backup of that old-source fixture. SHA-256: `d52cda4a4b9c673f5d8121b5528856f6b35f022fc3ea259bb9e23ab32a5530dd`. The writer's native-tool log is `swift_package_test_2026-09-09T06-43-42-174Z_pid88558_f03cc0df.log` in the local XcodeBuildMCP log directory.

## Source boundary

The mirrored model retains its original `note` and `keywords` schema fields. They are now internal legacy fields, cleared only after the local content is written, synchronized and read-verified. New capture persists private content before attaching the SwiftData session relationship; attaching the relationship first can implicitly insert the record, which the failure regression detected. New plaintext note/keyword content is never assigned to the disk model's legacy fields by the new capture/edit/tagging paths.

Notes are keyed by the existing distraction UUID in an adjacent `Anchor.store.private-notes` directory, excluded from backup, with private directory/file permissions. They have no CloudKit model, account transport, or cross-store relationship. Transient drafts are not relied on for restart persistence. In-memory preview/test stores keep their data in memory.

A local-only preflight opens and migrates existing data before any mirrored container opens. A migration failure keeps the existing local store open without CloudKit, shows a storage warning, and never substitutes an empty memory store for that failed migration. Failed capture/edit retains the draft and reports failure. Existing timeline state, IDs, relationships and non-note sync configuration remain intact.

Read screens, snapshot-backed analytics/export/MCP and note editing use local content. A corrupt vault raises an export error rather than silently replacing notes with empty strings. Notes absent on another device are labelled unavailable there. Deletion removes the local private record after metadata deletion succeeds; cleanup errors propagate. A conflicting synthetic older-device note is preserved as an alternate, not used to overwrite a newer local edit; the edit sheet exposes preserved earlier-device text.

## Local proof

Eleven focused migration tests exercise original-source disk migration, UUID/session/timing preservation, reopen/resume/free-decline without duplicate capture, note/keyword local persistence, edit/retry, deletion, blocked storage, corrupt storage/export refusal, and late legacy conflicts. The additional save-failure cases cover a successful vault write followed by failed metadata commit, retry without phantom or duplicate capture, capture-plus-pause rollback retaining the prompt and running timing, and an actual read-only SwiftData save failure. All 206 package tests pass with no warnings on 2026-09-09 (XcodeBuildMCP log `swift_package_test_2026-09-09T06-54-01-220Z_pid88558_fc864e0f.log`). The shared package also covers the existing habits, daily copying, project tags, pause/resume and Hub account boundaries. Exact dependency remains PersonalSyncKit `118fc5552b08078ac06e3339c0c65a304e103e7d`; no dependency was added.

The implementation was developed only in `/tmp/anchor-note-migration-20260909`. The owning checkout, owner stash, installed Mac/iPhone apps and stores were untouched during local proof. Native Swift package tests/builds ran through XcodeBuildMCP; no local foreground UI or simulator was used.

## Release limits

This is source/local-store evidence, not a production CloudKit or installed-device pass. Historical CloudKit copies, other old app versions, old export files and backups are not erased by this source change. Mixed-version provider import/export behavior and pending historical CloudKit transactions require explicit signed real-device qualification before release. Synthetic imported-field conflict tests do not establish that provider behavior.

Existing notarization, physical unlocked-device use, signed account authentication, and production CloudKit compatibility gates remain. Do not install or publish this migration over owner data solely because package or hosted tests pass. The privacy and migration issue remains open for those gates.

The older surrender/end path still performs multiple saves; this bounded migration does not establish transaction-wide rollback for an end failure after a successful capture. Capture/park and capture/pause failures have the explicit regression proof above.

## Exact source and hosted attempt

Build 25 source: `c9927b9b7abb7d2bec281a9c1d3d047f50a0483a`. [Hosted native review 34321290511](https://github.com/Significant-Hobbies/anchor/actions/runs/34321290511) failed before any job steps on 2026-09-09. GitHub reported: “The job was not started because recent account payments have failed or your spending limit needs to be increased.” No native UI/platform result exists for this source yet. The prior build-24 hosted pass does not qualify this migration.

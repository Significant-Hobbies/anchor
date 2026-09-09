# Scheduled-start transaction qualification — 2026-09-09

Baseline `861463726da6a26ed100d6565087e1f63d9e094a`. Bounded source repair under [#51](https://github.com/Significant-Hobbies/anchor/issues/51#issuecomment-5599058806); no owner app, store, account or physical device accessed. Build25 remains uninstalled/unreleased.

## Reproduction

The real `PlanBlockFocusStarter.start` saved its new session before saving the plan link and optional deliberate-replan event. A temporary test-only injection at that second save independently reopened the real synthetic disk store, confirmed one durable session with no plan link, then threw a controlled disk-full error. The controller stayed running and the in-memory block showed progress despite the unlinked disk state. One test failed three assertions (`swift_package_test_2026-09-09T08-46-28-051Z_pid88558_fa27e80b.log`); the MCP summary incorrectly counted failed assertions as tests. The temporary injection/test was removed after reproduction; no OS disk was filled and no owner data was used.

## Resulting behavior

`FocusController.start` now stages the optional plan link and deliberate-replan event with the new session before its existing save. A failed save restores precisely the modified block fields and removes only the newly inserted session/event. No new running timer is published. A successful save publishes the timer with its durable link already present. Today, Focus and the Mac mini timer use this shared operation; there is no later link-save commit in those start handlers.

An exact repeated request for the controller's currently active linked session returns it without ending/recreating it. This requires the matching session ID, normalized intent, duration, goal/project, notes and tags. Changed activity still ends the old session and saves the new one with a deliberate-replan event. A stale link or another block cannot trigger that reuse. Previously completed history remains committed separately if creation of its replacement fails. Existing UI reconciliation of historical plan state is unchanged; this does not claim transactional completion/reconciliation of every earlier plan entry.

## Evidence

- `scheduledTransactionRollbackRetryAndReopen`: the real handler reaches one save containing all three mutations; two failed attempts restore exact block state/timestamp. An unrelated later save and independent reopen reveal no phantom session/event. Retry saves project/notes, original authored title and deliberate replan once; duplicate invocation performs no new save.
- `activeLinkIdempotencyUsesExactSession`: same request reuses the active link; another block and a link to an older finished session create their own sessions.
- `linkedBlockChangedActivityStartsNewSession`: changing actual work/duration on the active block commits a new session and replan, while repeating that new request is inert.
- `failedScheduledReplacementKeepsHistory`: an already committed previous session end survives failed scheduled replacement and independent reopen.
- Four focused tests pass: `swift_package_test_2026-09-09T08-49-39-653Z_pid88558_8c28be6c.log`.
- Full owning-checkout suite: **219 passed, 0 failed, 0 skipped**, `swift_package_test_2026-09-09T08-50-22-199Z_pid88558_4305cc7d.log`. The pre-existing editable Hub override is preserved; isolated pinned-source results are recorded separately below.

- Clean isolated source copy resolves PersonalSyncKit `118fc5552b08078ac06e3339c0c65a304e103e7d` and passes **219/219**, `swift_package_test_2026-09-09T08-50-42-777Z_pid88558_d2f058d6.log`.
- XcodeBuildMCP 2.7.0 DebugLocal compile-only Mac/iOS/watchOS builds pass: `build_macos_2026-09-09T08-50-25-745Z_pid23449_ce80e46c.log`, `build_sim_2026-09-09T08-50-26-710Z_pid23633_186237ed.log`, `build_sim_2026-09-09T08-50-28-016Z_pid23826_e8ec85c1.log`. Existing asset/AppIntents metadata warnings are not presented as zero-warning builds. No simulator boot, app launch or install.

## Qualification limits

These are synthetic local-store handler tests and compilation, not rendered UI or signed-device/CloudKit evidence. No migration, schema, dependency, production configuration, build number, installation or release changed. #51 remains open for actual native/device acceptance; #52 retains historical CloudKit note-copy removal and mixed-version qualification. The dispatch-only native workflow has no automatic push CI. Prior baseline run34325826905 failed before any steps because of GitHub account billing/spending limits; no retry loop was started. Resolve that account gate before dispatching native-review.yml on the final source.

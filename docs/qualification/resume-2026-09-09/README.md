# Daily-flow audit and failed-resume repair — 2026-09-09

Baseline: `309a3ff0c23c9235426987c1fa13e3cc5935dbf0`. This is source and synthetic local-store qualification, not installed-device or CloudKit qualification. No owner app, account, store or device was opened; no installation or release occurred.

## Reproduced defect and contract

The reachable Resume action previously ignored a failed SwiftData save: the screen became running, return flags changed, completion notification/activity updates were published, and capture opened while reopening the store still showed paused. A real file-backed read-only store reproduced one failing test with four failed assertions (the MCP summary incorrectly called those four tests).

Resume now commits before publishing success. A failed save restores the exact paused account, pause timestamp and interruption return flags; no ticker restart, success notification/activity update or capture occurs. Paused controls show a retryable error on the main, compact and Watch surfaces. A successful retry clears the error and retains the existing optional capture-on-resume behavior.

## Requested daily workflow coverage

| Capability | Current implementation / evidence | Qualification boundary |
| --- | --- | --- |
| Direct unscheduled habit tracking | `HabitDayService` through HabitsScreen; `flexibleHabitCompletionIsUntimed` tests direct completion without invented duration or schedule | Prior simple-day native receipt covers save/relaunch; current source tests pass |
| Replacement habits | Habit editor stores behavior pattern / “Helps replace”; `replacementSuggestion`, `behaviorProfileRoundTrip` | Model/source evidence; no new owner habit created |
| Edit/copy daily schedules | DayScreen and `DayPlanService.copyDay`; `copyDayKeepsOnlyAuthoredContent`, weekday/template tests | Copy preserves projects/times and destination entries, excludes history |
| Project-tagged and spontaneous entries | PlanBlockEditor and project-linked starter; `startLinksSessionToPlan`, `unplannedSessionIsObserved` | Source/tests; “random” means owner-created spontaneous entry, not a random generator |
| Start / pause / resume / end | Shared FocusController; existing timer/controller tests plus real disk failure fixtures | Resume, start and unused extension persistence failures are covered below |
| Distraction logging | Shared capture, device-local note vault and migration fixtures | Local preservation only; historical cloud-copy erasure and mixed-version cloud behavior remain unqualified |

## Checks

- Original read-only-store negative control: `swift_package_test_2026-09-09T08-25-56-519Z_pid88558_2ec4999b.log` (one test, four assertions failed).
- Focused repaired tests: **2 pass**, `swift_package_test_2026-09-09T08-27-52-820Z_pid88558_b1d3342f.log`.
- Full working-checkout package suite: **210 pass, 0 fail, 0 skip**, `swift_package_test_2026-09-09T08-28-11-119Z_pid88558_407511cc.log`. The pre-existing editable Hub package override was preserved; clean pinned-source validation is recorded below separately.
- XcodeBuildMCP 2.7.0 DebugLocal compile-only builds pass for macOS, iOS 26.5 Simulator and watchOS 26.5 Simulator. Fresh derived data resolves pinned PersonalSyncKit `118fc5552b08078ac06e3339c0c65a304e103e7d`. No simulator boot or app launch/install. These builds compile the error labels; they do not prove rendered layout.
- Build logs: `build_macos_2026-09-09T08-31-26-023Z_pid62498_24d293e1.log`, `build_sim_2026-09-09T08-31-43-663Z_pid63398_0b636677.log`, `build_sim_2026-09-09T08-32-19-775Z_pid66125_34ddb63e.log`. Asset-catalog unassigned-child and skipped AppIntents metadata warnings are existing build warnings, not zero-warning results.

The retry fixture uses a real local disk store plus controlled failed writes: repeated failures retain one interruption, retry commits once, repeated Resume is inert while running, dismissing capture adds no duplicate, and independent reopen preserves the resumed account and return flag. All fixtures are synthetic and self-cleaning.

Clean isolated package copy with the pinned Hub revision also passes **210/210**, `swift_package_test_2026-09-09T08-34-55-227Z_pid88558_59e728d8.log`. Initial isolated attempts omitted app-source/assets and then workflow fixtures needed by source-contract tests (202/210 and 209/210); restoring those unchanged fixture inputs produced the clean pass. No dependency changes or product failures were hidden.

## Remaining gates

[#51](https://github.com/Significant-Hobbies/anchor/issues/51) remains open. The start/extension follow-up below repairs those source failures; extension still has no current UI caller. A later failure saving a successfully started session’s schedule link remains a separate, non-atomic operation with explicit UI wording. This slice does not claim to fix that second commit. Current owner-device acceptance, signed distribution and cloud qualification remain open; package/build checks do not close them. Hosted native review was previously blocked before steps by GitHub account payment/spending limits ([34325826905](https://github.com/Significant-Hobbies/anchor/actions/runs/34325826905)); this is an infrastructure gate, not a test result. Historical CloudKit note-copy/mixed-version gates remain in [#52](https://github.com/Significant-Hobbies/anchor/issues/52).


## Follow-up: start and extension persistence

After resume commit `f2b3b4c`, two new disk-backed negative controls reproduced ten failed assertions: failed start published a running session and could later persist its phantom record; failed extension resumed/increased the account in memory despite a failed write. Log: `swift_package_test_2026-09-09T08-36-48-992Z_pid88558_de065ff7.log` (two tests, ten assertions; MCP summary conflates them).

`start` now returns an optional saved session. Failure deletes only the new unsaved session and publishes no running state, notification or activity. Failed replacement end preserves the current session; if ending succeeds but new creation fails, the committed finished history remains. All production callers handle failure: the main composer retains its complete draft, compact input remains, Watch displays an error, and scheduled starts neither navigate to a nonexistent session nor attach/replan a block. The actual composer submission handler removes only a goal it just created on failure; preexisting goals remain untouched. Successful start preserves the existing field-clearing behavior. Extension restores the previous account and state on failure and preserves its existing successful timer semantics; no new extension control was added.

Evidence:

- Actual `StartComposerDraft.submit` tests use disk-backed stores and the real controller with controlled write failure, for both new and preexisting goals. Repeated failures retain all draft fields; a subsequent unrelated save and reopen reveal no phantom session/goal; retry records project, notes and tags once.
- Actual `PlanBlockFocusStarter.start` failed-create test proves no session link, start timestamp or divergence record survives, including after independent reopen.
- Controller tests prove start retry, both replacement failure boundaries, extension rollback/retry, unchanged earned time and restart persistence.
- Focused start/extension tests: 2 pass (`swift_package_test_2026-09-09T08-38-21-998Z_pid88558_89dfb1b8.log`); caller tests: 2 tests pass, including two parameter cases for draft preservation (`swift_package_test_2026-09-09T08-40-18-861Z_pid88558_37dd995f.log`).
- Full suite: **215 pass, 0 fail, 0 skip** in the owning checkout (`swift_package_test_2026-09-09T08-40-48-922Z_pid88558_00acc54f.log`) and clean pinned-dependency copy (`swift_package_test_2026-09-09T08-41-38-402Z_pid88558_419ea8f6.log`).

Final follow-up DebugLocal compile-only checks also pass on all three platforms: `build_macos_2026-09-09T08-41-26-075Z_pid1418_8b099b6c.log`, `build_sim_2026-09-09T08-41-27-092Z_pid1504_5fea3105.log`, and `build_sim_2026-09-09T08-41-28-369Z_pid1597_ff20e38b.log`. No app or simulator was launched or installed; rendered error-state layout is not claimed.

This is still uninstalled build25 source. No build number, entitlements, migration, cloud config or production data changed. The repository’s native workflow is dispatch-only; no automatic CI ran for the resume push. The previous exact baseline run34325826905 has no executed job steps; no billing retry loop was started. A hosted/device acceptance pass must be obtained after the account billing/spending gate is resolved, before treating this as installed native qualification.

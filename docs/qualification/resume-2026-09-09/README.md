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
| Start / pause / resume / end | Shared FocusController; existing timer/controller tests plus real disk failure fixtures | Resume fixed here; initial start and unused extension save handling remain separate work |
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

[#51](https://github.com/Significant-Hobbies/anchor/issues/51) remains open. `start()` still publishes before checking its initial save; `extend(byMinutes:)` also ignores persistence failure and has no current UI caller. Both need a bounded atomic-persistence follow-up, including caller behavior. Current owner-device acceptance, signed distribution and cloud qualification remain open; package/build checks do not close them. Hosted native review was previously blocked before steps by GitHub account payment/spending limits ([34325826905](https://github.com/Significant-Hobbies/anchor/actions/runs/34325826905)); this is an infrastructure gate, not a test result. Historical CloudKit note-copy/mixed-version gates remain in [#52](https://github.com/Significant-Hobbies/anchor/issues/52).

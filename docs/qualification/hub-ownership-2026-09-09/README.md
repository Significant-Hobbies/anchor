# Build 24: history ownership and reachable iPhone start

Build 24 is under qualification. It is not yet a public release or a claim of signed-in device continuity.

## Changes

A synthetic regression reproduced the same local focus session being exported as A and then automatically as B. Local history now needs explicit approval for the displayed, server-verified Hub account. Approval persists on the device; each session also carries an optional owner through SwiftData/iCloud. Matching-owner sessions alone are exported. Old unscoped queues remain untouched. New phone/Mac sessions capture the approved owner offline; unowned sessions arriving from other devices need approval. Hub remains outbound-only.

Approval refuses active focus before requesting identity, survives retry after file-write failure, fails closed on malformed ownership, and cannot overwrite a newer account's status after a delayed reply. Session ownership survives reopening a real local SwiftData store. The new optional CloudKit field still needs production compatibility verification.

An iPhone onboarding journey exposed the keyboard toolbar overlapping the bottom Start focusing button. While editing, the start action now lives in the keyboard toolbar; the bottom action returns when editing ends. Both intention and notes support explicit focus/dismissal. The journey verifies the start action remains hittable with the keyboard open.

## Evidence collected locally

- 195 package tests passed: `swift_package_test_2026-09-08T19-18-12-563Z_pid50013_6f2ba254.log`.
- All 8 iPhone UI journeys passed after the keyboard repair: `test_sim_2026-09-08T19-14-15-177Z_pid73475_b9260d4a.log`.
- Watch simulator build passed: `build_sim_2026-09-08T19-18-00-495Z_pid76800_b621cf0c.log`.
- Offscreen Mac catalog build passed and rendered 27 surfaces. Sampled phone Focus, Today and Habits plus Mac Settings images were legible without obvious clipping. This sample does not establish every rendered surface's quality or signed-in account appearance.
- On-device tagging diagnostic passed all 8 distraction cases and 4 goal cases using Apple Intelligence: `build_run_spm_2026-09-08T19-19-13-565Z_pid77844_7fd0fd8a.log`. The diagnostic prints a store path but does not instantiate the owner store; it classifies synthetic examples.
- Mac UI suite: pending at this checkpoint.

Logs and result bundles are under the local XcodeBuildMCP `fleet-167b0b9d8f42` workspace. Testing used an isolated checkout and synthetic stores/accounts, not the owner's saved data. Package checks used the installed Swift toolchain; native iPhone/Watch builds used Xcode 26.6.

## Remaining qualification

Hosted CI, signed build/install/launch, real approval and two-device convergence remain open in [issue 51](https://github.com/Significant-Hobbies/anchor/issues/51). Verify production support for `FocusSession.hubAccountID` along with the previously pending schema fields. No production schema was changed here.

Privacy requires a separate source/provider audit: `Distraction.note` is a persisted field in the CloudKit-backed schema, although the repository contract says distraction notes never leave the device. Transport tests establish exclusion from Hub payloads only. Do not infer iCloud exclusion or full privacy readiness from those tests.

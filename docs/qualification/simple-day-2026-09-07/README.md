# Anchor simple daily loop qualification

Tracking: [issue 51](https://github.com/Significant-Hobbies/anchor/issues/51).
Source baseline: `1e62db0d0a99a88d8f76cf89aba8c1dc2bdf720b`; implementation
is in the commit containing this receipt. Version 1.0, build 22.

Implemented: direct habit check-off/undo without a timed block; optional
scheduling; selected-day editing and copying without replacing destination
entries; project context preserved into sessions; spontaneous entries; pause
and return from interruption capture. Removed progression and daily-confirmation
prompts from the main loop while retaining stored history.

## Verified

- Shared package: 23 UI/source-contract tests and 162 core tests pass, including
  wall-clock pause recovery, no duplicate interruption after declining the
  resume prompt, day-copy history isolation, and project propagation.
- iPhone simulator (iOS 26.5): focused pause/return journey, habit check-off
  persistence through relaunch, and day-copy persistence all pass: three actual
  tests, zero failures. Logs are adjacent. These are isolated synthetic stores.
- Native visual catalog: 27 rendered surfaces; manually reviewed the changed
  Today widths, Habits and editor. The scoped design receipt passes. Images are
  macOS offscreen renders, including phone-sized layouts, not device screenshots.
- The initial Release build 22 was Apple Development-signed and installed on the
  owner's iPhone. It retains CloudKit and the app group. This is a local
  development installation, not an App Store/TestFlight build or production-sync
  qualification. The final source also built successfully with stable Xcode
  26.6, passed signature verification, and was installed on the phone.
  `phone-release-stable.log` and `phone-install-stable.log` record that result.
- CloudKit Development schema exported and verified with the two additive
  `CD_projectID` string fields on `CD_PlanBlock` and `CD_ScheduleTemplate`.
  No existing fields or owner records were removed.

## Open release gates

- Physical iPhone first-run/use is unverified while the phone is locked.
- Local Xcode 27 beta Mac UI execution could not connect to the test runner;
  no product assertion ran. Stable Xcode 26.6 retry and hosted native checks
  are separate evidence, pending at this receipt's creation.
- Production CloudKit still needs the two additive fields promoted through the
  signed-in CloudKit Console. The CLI rejects schema-management operations for
  Production, and regular Chrome currently shows Apple's sign-in page.
- Installed Mac `/Applications/Anchor.app` remains build 21. Do not replace it
  with a production-sync build 22 until the production fields are verified.
- No TestFlight upload, Apple processing, or cross-device production sync is
  claimed. Issue 51 remains open for actual phone/Mac release qualification.

Design evidence: [`artifacts/design/simple-day-20260907`](../../../artifacts/design/simple-day-20260907).

## Hosted full-suite result and correction

[Run 34151609977](https://github.com/Significant-Hobbies/anchor/actions/runs/34151609977)
passed the full iPhone suite and Watch build, but failed the final gate because
three Mac tests failed. A step's `conclusion: success` was misleading here: its
`continue-on-error` policy masked `outcome: failure` until the final guard.

Two Mac tests still used the removed usual-week setup button and button-role
queries for a native popup menu. The mini-timer test timed out while scanning
the entire accessibility tree for the saved title. Updated them to enter the
weekly manager through a real recurring entry, use menu-button/menu-item roles, and
query the actual title text directly. These preserve the tested requirements;
no assertions or product capabilities were removed. The corrected native suite
requires a fresh hosted run before claiming a pass.

The exported failing Mac UI hierarchy identifies the habit control explicitly
as `MenuButton`, labeled `More actions for Two-day reset`; the corrected query
uses that observed native role. The mini-timer spindump shows an idle app main
thread during the snapshot timeout, supporting a narrower text query rather
than claiming the product was busy or changing its timing model.

Stable-Xcode ReleaseDirect archive/export and Developer ID DMG verification
succeeded. Notarization is blocked by the missing documented `anchor-notary`
Keychain profile. The signed package is prepared, not installed or released.
A fresh Production CloudKit reread still lacks the two project fields.

## Phone density follow-up

The actual iPhone capture exposed an overly tall Today header. Switched only
that scene to the existing compact style and shortened its guidance. The
stable-Xcode copy/persistence journey passed again, and the actual screenshot
and three new catalog widths were inspected. Evidence is in
`compact-iphone-test.log` and `artifacts/design/simple-day-20260907/`.

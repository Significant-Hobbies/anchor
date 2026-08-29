---
name: anchor-review-readiness
description: Run Anchor's fail-closed Mac and iPhone review-readiness audit. Use before calling Anchor ready, shipping a build, submitting for App Review, or after owner testing exposes cross-surface quality or data-integrity concerns.
---

# Anchor Review Readiness

Prove the current Anchor source and exact release candidate are review-ready. A
passing compiler is necessary but insufficient: every product capability needs
automated evidence, observed device evidence, or an explicit unresolved gate.

## Boundaries

- Read `AGENTS.md`, `PRODUCT.md`, `PROJECT_STATUS.md`, and `Apps/project.yml`
  before interpreting results.
- Never upload, submit, notarize, deploy, delete data, reset a device, or mutate a
  production account. Those remain separately authorized release actions.
- Keep distraction notes on device. Treat possible demo/test-store egress or
  unproven imported-history provenance as a blocker.
- Keep source, tests, simulator, physical device, archive, provider processing,
  installation, and owner acceptance as separate evidence gates.
- Use stable Xcode for release evidence. A beta-toolchain pass is not a release
  pass.

## Run

Read [the feature matrix](references/feature-matrix.json), then run:

```bash
node .agents/skills/anchor-review-readiness/scripts/review-readiness.mjs \
  --full \
  --policy-checked YYYY-MM-DD
```

`--full` is intentionally non-disruptive on a working Mac: it builds every
native target and renders the page catalog offscreen, but it does not launch or
drive Anchor, Simulator, or System Settings. Run the manually dispatched
`Anchor native review` GitHub Actions workflow for interactive Mac/iPhone UI
evidence. `--allow-disruptive-local-ui` exists only for an isolated runner or a
local machine the owner has explicitly made available for UI automation.

Before supplying `--policy-checked`, refresh these official sources and record
the current date:

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/news/upcoming-requirements/
- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- https://developer.apple.com/documentation/bundleresources/privacy_manifest_files

Add `--archive /absolute/path/to/Anchor.xcarchive` only for the exact candidate
being qualified. Add `--physical-iphone-observed` only after the current build
has actually launched on the owner's phone. Add
`--authenticated-data-observed` only after a fresh authenticated account has
been observed without unexplained old history. Add `--isolated-ui-observed`
only after the complete hosted Mac and iPhone workflow passes for the exact
commit. Add `--production-cloudkit-observed` only after the current SwiftData
schema imports and exports successfully against Production CloudKit.

The helper uses the XcodeBuildMCP CLI for native builds and isolated Mac/iPhone
test execution when MCP tools are not loaded in the current agent session. If the MCP server is loaded,
follow the installed `xcodebuildmcp` skill: show session defaults first, enable
the macOS, simulator, device, logging, and UI-automation workflows, and preserve
the same destinations and report boundary.

## Interpret

Reports are written under ignored `build/review-readiness/<timestamp>/` as JSON,
Markdown, and per-check logs.

- `READY`: every blocking automated and manual gate has current evidence.
- `NOT READY`: at least one blocker or manual gate is unresolved.
- Warnings are cleanup or freshness concerns; they never conceal a blocker.
- A skipped check is not a pass.

Use the installed `app-store-review` skill to interpret policy, privacy,
entitlement, metadata, and archive findings. Re-fetch current Apple facts rather
than trusting the skill's dated examples.

Do not fix product defects merely because this audit discovered them unless the
user also asked for implementation. Safe fixes stay small and are followed by a
fresh full run.

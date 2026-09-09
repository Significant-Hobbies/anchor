# Mac runner diagnosis — 9 September 2026

The original runner failure now has an evidenced immediate cause: **Gatekeeper
terminated PID 51816 before its XCTest connection**. This does not establish an
Accessibility/TCC denial or a failed Anchor product assertion.

The bounded [unified-log excerpt](gatekeeper.log), covering only the exact runner
identity/path hash and nine seconds around its launch, records:

- XProtect reporting an unresolved CoreSymbolicationDT framework path inside the runner.
- Gatekeeper evaluating `com.apple.XCTRunner` under the Anchor test-runner bundle,
  showing a prompt, then terminating PID 51816 at 14:28:52.853 local time.

No explanation is inferred for the prompt's disposition. The earlier receipt
correctly reported its then-unknown cause; this adds later read-only evidence.

## One build-only diagnostic

On exact source `c3704f6a8ceb1771621605d38e981ec8fe449989`, XcodeBuildMCP 2.7.0
`macos build --build-for-testing`, stable Xcode 26.6 and DebugLocal compiled in
39.647 seconds. It produced original DerivedData products and an exported
`.xctestproducts` bundle. **Neither the runner nor the app was executed.**

The [artifact comparison](artifact-comparison.json) shows identical runner and
XCTestCore executable hashes in original and exported products. Both runners
retain the Xcode template executable identity `com.apple.XCTRunner` and lack a
CodeResources file. Both fail `codesign --verify --deep --strict` with:

> code has no resources but signature indicates they must be present

The XCTestCore relative LC_RPATH reaches the existing CoreSymbolicationDT inside
the installed Xcode framework layout, but reaches a nonexistent SharedFrameworks
path in **both** generated runner layouts. The standalone framework in Xcode passes
signature verification. The original Xcode runner executable carries a signature,
but its template app bundle is not itself a ready-to-run signed application.

This rules out export-only corruption as the complete explanation. Gatekeeper's
rejection is confirmed; the precise contribution of the invalid bundle signature
versus the unresolved scanner path is not isolated by this build-only comparison.

## Supported next step

Cached MCP source (`build/utils/test-common.js`, lines 159–214) always requests
`build-for-testing -testProductsPath` and then `test-without-building` on that
export. `preferXcodebuild` does not remove this two-stage path. The supported
`--xctestrun-path` mode can run a prepared file, but the original runner already
has the same signature defect. No path-only retry is justified.

Review a properly development-signed isolated UI-runner configuration using the
existing development identity, preserving the local app identity, explicit UUID
store/vault and disabled external sync. Verify the resulting bundle before any
execution. This is a proposed next investigation, not a tested remedy or an
approved change to signing. Do not ad-hoc re-sign, remove quarantine, disable
Gatekeeper/TCC, modify production signing or launch the owner's installed app.
The [official MCP tools reference](https://www.xcodebuildmcp.com/docs/tools) describes
prepared test inputs; the cached 2.7.0 implementation was inspected for this exact
invocation contract.

The [receipt](receipt.json) preserves the generated test-host paths. No product
source, signing/profile setting, owner store, installed app or stash changed.
Task-owned diagnostic products are removed after retaining these compact receipts.

## Authorized signing-only build comparison

A second build-for-testing used invocation-only overrides:
`CODE_SIGNING_ALLOWED=YES`, `CODE_SIGNING_REQUIRED=YES`,
`CODE_SIGN_STYLE=Automatic`, `CODE_SIGN_IDENTITY=Apple Development`, and
`DEVELOPMENT_TEAM=8F7LXHTJZR`. It retained DebugLocal and requested no provisioning
updates. Existing signing resolved without changes to profiles or project files.
The build passed in 35.930 seconds. Its compile log confirms ANCHOR_LOCAL_ONLY.

Both original and exported app/runner now pass strict/deep signature verification,
with the correct bundle identities, team and sealed resources. The local app has
no CloudKit/app-group entitlement; Xcode adds normal debugger/test allowances.
[Signed artifact comparison](signed-artifact-comparison.json) records the exact
results. The relative CoreSymbolication path is still absent. This repairs the
observed signature defect in a diagnostic artifact, but does not yet prove that
Gatekeeper will accept execution or that the UI journey works. No runner/app was
executed during either build-only diagnostic.

## One authorized prepared-runner execution

The properly development-signed exported artifact was then selected through MCP
for only `testFocusInterruptionAndReturnJourneyPersists`, with a 120-second test
cap and the existing UUID store/vault fixture. The attempt ended after 62.640
seconds. Runner PID 43163 connected to testmanagerd and requested automation mode,
then failed after its 60-second automation initialization timeout. **No product
assertion ran, no screenshot was produced and the fixture directory was never
created.** The runner exited; the native resource slot was released.

The [same-run log](automation-initialization.log) proves the new boundary:
connection at 15:39:34.945, automation request/client registration at
15:39:35.002, timeout at 15:40:35.024. TCC records only a DeveloperTool preflight
with `Auth Right: Unknown (None), DB Action:None`. There is no explicit permission
denial/grant or evidenced user action to prescribe. A device-discovery warning in
the tool output is separate from this Mac XCTest system failure; no physical
app/device action was requested.

Normal development signing resolved the earlier pre-connection failure for this
attempt. It does **not** qualify the daily loop: working macOS XCTest automation
initialization is the remaining local gate. Do not infer that Accessibility/TCC
must be toggled from a generic timeout. No retry or broader test was performed.
All signature/privacy safeguards remained in place; no ad-hoc signing or system
security changes were made. Owner-installed apps, stores and the existing stash
remain untouched. [Issue 51](https://github.com/Significant-Hobbies/anchor/issues/51)
retains rendered daily-loop and release acceptance.

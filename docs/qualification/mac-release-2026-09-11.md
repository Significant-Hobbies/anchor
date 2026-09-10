# Mac build 25 qualification — 11 September 2026

Product source: `56d5a67b7783d66623f77d3cb3f9ebcc710365f1`. Its only change
from hosted-tested `077f8564ee3e85631f1807c365b03e9d283c41db` is the physical
iPhone UI test's sandbox path; production code is identical.

## Verified

- Hosted native review [34470263891](https://github.com/Significant-Hobbies/anchor/actions/runs/34470263891)
  passed 219 shared tests, 14 Mac UI tests and 8 simulator iPhone UI tests.
  The Mac focus/interruption/pause/resume/history/relaunch journey passed in
  46.908 seconds. This supersedes the earlier hosted billing-blocked receipts.
- The local generated Xcode project was stale and initially produced build 23.
  Regenerating with the repository's `xcodegen generate` produced build 25.
  Neither ordinary build was installed. The generated project remains untracked.
- `scripts/release-mac.sh` archived and exported build 25 with Developer ID
  signing, hardened runtime, Production CloudKit, the Anchor container and no
  debugger entitlement. Strict/deep signature verification passed.
- Signed `dist/Anchor-1.0-25.dmg` SHA-256:
  `e891773b8b857576115a0994e8a9d5d76dc88dbf8cd4d9dacbad4b1c076868c5`.
- The strengthened release-script validators were run against the actual
  ordinary build and distribution export. Both gates reject the ordinary
  build and accept the distribution export. Shell syntax validation passed.

## Launch limitation

XcodeBuildMCP launched the exported app as PID 37577; its process remained
alive on the subsequent check and was then stopped through the tool. This is
launch proof only. The intended isolated store directory was absent. Inspection
of the installed tool showed that `launch_mac_app` does not forward session
environment settings. The launch therefore cannot be claimed as isolated or as
an account-sync test. A read-only owner-store inventory was denied by macOS;
no bypass was attempted. Whether that launch migrated existing local data is
unverified. No user action, record creation or deletion was performed in the UI.

## Remaining

- The release script skipped notarization because `ANCHOR_NOTARY_PROFILE` was
  unset. This DMG is not a notarized public release and was not published.
- `/Applications/Anchor.app` remains build 21; no installed bundle was replaced.
- The phone's previously installed development-signed build 25 does not declare
  a CloudKit environment. Matching the production export's container name alone
  does not establish production database continuity.
- Production schema compatibility, historical note copies, account round trips
  and signed mixed-version behavior remain unverified. Issues 51 and 52 stay open.
- The native computer-use connection failed at startup. No local rendered
  screenshot or UI acceptance is claimed from this attempt.

The exported app and signed DMG are retained as release artifacts. Earlier
release build output was preserved by the existing release script. No owner
store cleanup, credential change or production configuration change was made.

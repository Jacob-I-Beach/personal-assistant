# Implementation status

**Current: 1.0.2 build 13 is packaged for an in-place iPhone update.** Native run 38199838169 reproduced the prior Tailscale TLS error (-1200), then passed the repaired pinned-HTTPS connection and four additional transport checks. The physical archive and 186 shared-core tests pass. The PC companion remains 1.0.1 with its existing certificate, sign-in and pairing. Physical iPhone scanning is pending. Read [the repair change list](Documentation/RELEASE_102.md), [build evidence](Documentation/ReleaseValidation102.json) and [phone acceptance](Documentation/DeviceValidation102.json).

The release history below retains the evidence and limitations of earlier updates.

**1.0.0 build 11 historical handoff.** The Windows computer companion was packaged and its launcher/setup verified. The then-installed baseline was 0.9.0 build 10, established by the device reports. Preserve the current installation and its data.

The final archive matches `04b5737405591c8ec548623c989ec6dc8fd489c5`, [run 38188054967](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38188054967). It passes 185 shared-core and eight EventKit checks and includes a physical ARM64 Live Activity extension. Seven focused platform checks and the native Computer/Contacts interface scenario passed in [run 38185837305](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38185837305); those inspected screens remain unchanged. Earlier 1.0 foundation evidence covers the Health/callback repairs, alignment and Home. The full legacy UI suite was not repeated.

Read [the change list](Documentation/RELEASE_10.md), [build receipt](Documentation/ReleaseValidation10.json), [visual review](Documentation/VisualReview10.json) and [phone checks](Documentation/DeviceValidation10.json).

This update adds durable computer-owned tasks with an independent ChatGPT plan sign-in; isolated file-backed Python and rich document inspection; native contacts/email/attachment workflows; stable text/surface revisions; maintained projects; combined context search; recurring/all-day planning and recorded batch outcomes; and bounded research/drafting schedules. It repairs the evidenced Health authorization/callback crashes, short-message alignment, local guided tool schemas and Home freshness. Computer work survives phone disconnection; native phone actions wait for the phone.

Health input: `../PersonalAssistant-iPhone/1.0.0/PersonalAssistant-HealthKit.ipa`, SHA-256 `c9561e0fed4cb08b6aec4c01e4dec92a88ce99290e9e6a7879505b9513c4a428`. Use the confirmed r2 helper at `../Tools/iLoader-Assistant-Health/r2/iLoader-Assistant-Health.exe` and the same Apple account. Keep the app installed. The companion executable is `../PersonalAssistant-Computer/1.0.0-release/PersonalAssistant-Computer.exe`; keep its complete folder together.

Ten companion checks cover encrypted storage, paired HTTPS, disconnected completion, phone outcomes, cancellation, context excerpts and bounded schedules. Real Docker execution generated and reopened a workbook/PDF and rendered document pages. Actual computer ChatGPT authorization, real iPhone pairing, Health access and a background/locked-phone run remain user-operated acceptance steps. Sustained off-app push updates, an away-from-home private route and general phone UI control are not claimed as delivered.

The repository remains public by explicit user choice. Standard xcode-27 compute is free under the verified current policy; storage is separate. Private data, device logs, pairing records and credentials stay outside Git.


## 1.0.1 repair handoff

Packaged build 12 from native source c4518cc, run 38196469130. Everyday replies use the direct ChatGPT connection; optional PC tools, saved background handoff and completed-output parsing are implemented. 186 Windows/Mac core tests, 15 synthetic companion checks, and the focused native coverage documented in ReleaseValidation101.json pass. The corrected Windows service, retained account/pairing, Tailscale route, scoped firewall, and startup entries are verified. iPhone installation, all-selected Health authorization and real background/Lock Screen behavior remain physical checks. Fully suspended Live Activity updates still need remote push provisioning. See RELEASE_101.md for added, changed, removed and pending scope.

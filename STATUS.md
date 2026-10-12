# Implementation status

**1.0.0 build 11 is packaged for user-operated in-place installation.** The Windows computer companion is also packaged and its launcher/setup are verified. The installed baseline is 0.9.0 build 10, established by the device reports. Preserve that installation and its data.

The final archive matches `04b5737405591c8ec548623c989ec6dc8fd489c5`, [run 38188054967](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38188054967). It passes 185 shared-core and eight EventKit checks and includes a physical ARM64 Live Activity extension. Seven focused platform checks and the native Computer/Contacts interface scenario passed in [run 38185837305](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38185837305); those inspected screens remain unchanged. Earlier 1.0 foundation evidence covers the Health/callback repairs, alignment and Home. The full legacy UI suite was not repeated.

Read [the change list](Documentation/RELEASE_10.md), [build receipt](Documentation/ReleaseValidation10.json), [visual review](Documentation/VisualReview10.json) and [phone checks](Documentation/DeviceValidation10.json).

This update adds durable computer-owned tasks with an independent ChatGPT plan sign-in; isolated file-backed Python and rich document inspection; native contacts/email/attachment workflows; stable text/surface revisions; maintained projects; combined context search; recurring/all-day planning and recorded batch outcomes; and bounded research/drafting schedules. It repairs the evidenced Health authorization/callback crashes, short-message alignment, local guided tool schemas and Home freshness. Computer work survives phone disconnection; native phone actions wait for the phone.

Health input: `../PersonalAssistant-iPhone/1.0.0/PersonalAssistant-HealthKit.ipa`, SHA-256 `c9561e0fed4cb08b6aec4c01e4dec92a88ce99290e9e6a7879505b9513c4a428`. Use the confirmed r2 helper at `../Tools/iLoader-Assistant-Health/r2/iLoader-Assistant-Health.exe` and the same Apple account. Keep the app installed. The companion executable is `../PersonalAssistant-Computer/1.0.0-release/PersonalAssistant-Computer.exe`; keep its complete folder together.

Ten companion checks cover encrypted storage, paired HTTPS, disconnected completion, phone outcomes, cancellation, context excerpts and bounded schedules. Real Docker execution generated and reopened a workbook/PDF and rendered document pages. Actual computer ChatGPT authorization, real iPhone pairing, Health access and a background/locked-phone run remain user-operated acceptance steps. Sustained off-app push updates, an away-from-home private route and general phone UI control are not claimed as delivered.

The repository remains public by explicit user choice. Standard xcode-27 compute is free under the verified current policy; storage is separate. Private data, device logs, pairing records and credentials stay outside Git.

# Implementation status

**0.8.0 build 9 is packaged for user-operated installation and phone validation.** The last phone-confirmed version is 0.7.1 build 8, with retained chats and repaired Calendar/Reminders Save/relaunch. 0.8 installation and real-device background, Health and haptic checks remain pending.

[Native validation](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38131578620) passed the iPhone build, 173 shared-core tests, 8 EventKit regression tests and 33 platform tests. 16 of 17 UI scenarios have passing coverage: three passed in the latest run and 13 retain evidence from unchanged production paths. The remaining file-workflow test tapped a disabled button during fixture initialization. Its readiness wait is corrected but was not rerun after the user asked whether additional testing was needed; that workflow remains pending. The overall workflow is therefore recorded as failed, not a fully green suite. Native screenshots were inspected. The Release package matches source `287f4b2e18d9e5a14a724f8e27bf23afc9f6bf15`. See [release scope](Documentation/RELEASE_08.md), [build receipt](Documentation/ReleaseValidation08.json), [visual review](Documentation/VisualReview08.json) and [phone checklist](Documentation/DeviceValidation08.json).

The candidate unifies Library entry points and connection navigation, gives the composer full text width, makes latest-scrolling immediate and disclosure headings stable, improves readable result cards, adds quiet feedback and copy confirmation, removes repeated ordinary network prompts, and adds model-aware context settings plus compact app orientation. Background progress follows actual transport/tool bytes. A capability-aware local signing helper supports a separate HealthKit input; the actual signed entitlement and Health permission must be checked on the phone before claiming access.

## Packages

- Health input: `../PersonalAssistant-iPhone/0.8.0/PersonalAssistant-HealthKit.ipa`, SHA-256 `d9ed6fcc7690115ba4b431f1c31c3518ef22db92db46e42c9229acd30fd96777`.
- Normal input: `../PersonalAssistant-iPhone/0.8.0/PersonalAssistant-iPhone-only.ipa`, SHA-256 `1aa3571d7cceb59116aed20fbd180db3cf64ecd4064092dfea4a21cee0e8c715`.
- Local helper: `../Tools/iLoader-Assistant-Health/r2/iLoader-Assistant-Health.exe`; source patch and provenance are alongside it.

## Validation cost policy

Jacob explicitly chose public source for free standard-runner development. Visibility and the standard `xcode-27` label were checked. New standard public compute is free under GitHub policy; storage is separate and artifacts have short retention. Historical fully-billable estimates in BuildValidation.json are not net account charges. Private billing data stays outside Git. Recheck visibility and runner class before future dispatches.

## Loader correction and scope audit

The original Windows helper attempted to load a development server because it lacked Tauri production asset handling. Revision 2 uses the production build path and includes a focused embedded-interface check. The user confirmed the normal loader interface opens. Apple provisioning and phone Health access remain pending. See [the complete request-to-implementation audit](Documentation/REQUEST_AUDIT_08.md) for implemented, partial, deferred and unverified work.

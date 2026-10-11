# Implementation status

**0.9.0 build 10 is packaged for user-operated installation.** The preceding 0.8 update is user-confirmed to work generally, with the exceptions recorded in DeviceValidation08.json. Physical 0.9 behavior remains pending.

Passed 177 core and eight EventKit checks in [the final run](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38152677219). The four focused interface scenarios have passing coverage: 1 in the final run, with three previously passing scenarios and 36 platform checks retained from [run 38149397041](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38149397041) against unchanged production paths for those checks. The final run covers the Health selection view, including results visible above the keyboard. Native screenshots were inspected. The iPhone archive matches source `6a681c168a11743fb4d28276a2598b6d245b7f81`. The full legacy UI suite was not repeated.

Read [the change list](Documentation/RELEASE_09.md), [build receipt](Documentation/ReleaseValidation09.json), [visual review](Documentation/VisualReview09.json) and [phone checks](Documentation/DeviceValidation09.json).

The update combines thinking/context under the brain, corrects catalog-default capacity handling, improves compact question and inline-answer presentation, removes the menu Library shortcut, keeps deliberate continuation available, improves attention and return-to-task handling, and expands selected Health reads. Background failure causes remain evidence-dependent; model output budgets, network timeouts and iOS processing endings are distinct.

Health input: `../PersonalAssistant-iPhone/0.9.0/PersonalAssistant-HealthKit.ipa`, SHA-256 `1fe2ff173d87349d33963411414b31b0af2a46df20c030dec96bd699647b7f0b`. Use the confirmed r2 helper at `../Tools/iLoader-Assistant-Health/r2/iLoader-Assistant-Health.exe` with the same Apple account. Keep the app installed.

The repository remains public by explicit user choice. Standard xcode-27 compute is free under the verified current policy; storage is separate. Private data, device logs, pairing records and credentials stay outside Git.

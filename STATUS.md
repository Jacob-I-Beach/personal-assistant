# Implementation status

**0.7.1 build 8 is built and verified for an in-place repair of the Reminders startup crash.** Jacob confirms the in-place update works with both Calendar and Reminders enabled: Save succeeds, close/reopen checks succeed, and previous chats remain. Eight 0.7.0 build 7 phone reports identified a Swift main-actor assertion inside the Reminders callback. Jacob confirmed that temporarily disabling planning permissions restores launch. Preserve the installation and chats.

## Current repair evidence

[Run 38115961045](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38115961045) passed **161 shared-core tests plus 8 native EventKit regression tests** and built the physical iPhone Release archive from `7f76edb3ead452167ebd1e3702cb8d329ef38193`. The EventKit tests use the same nonisolated, Sendable completion factory as the app and invoke it from a background queue. They also exercise overlapping fetches, missing results, incomplete native objects, due dates, completion filtering, and version snapshots. No simulator UI suite was repeated for this narrow repair.

The iPhone-only input is `../PersonalAssistant-iPhone/0.7.1/PersonalAssistant-iPhone-only.ipa`, 20,846,311 bytes, SHA-256 `af8d2567181ccb26cfed578b3198fe23aa39908b32671a17b50f6dba40e277c1`. Package inspection verifies the existing bundle identity, physical ARM64/iOS binary, dependency pins, Metal assets, Siri metadata, privacy/background configuration, and absence of debug backends. See [repair scope](Documentation/RELEASE_071.md), [build evidence](Documentation/ReleaseValidation071.json), and [physical checklist](Documentation/DeviceValidation071.json).

Install over the current app with the same iLoader account, verify About 0.7.1 build 8, then restore Calendar/Reminders permissions, save selected sources, and close/reopen twice. Jacob completed this checklist successfully on October 11. A subsequent USB lookup/crash pull was unavailable, so physical acceptance is based on his direct test confirmation, not a claimed post-update log inspection. Raw device reports remain outside Git.

## Validation budget

This repair used an estimated **USD 0.620**. The recorded cumulative estimate is **USD 32.178**, leaving **USD 0.404** under the authorized bookkeeping ceiling. Rounded durations include failed/cancelled jobs; this is a compute estimate, not an invoice. No new uncapped validation is authorized.

## Retained 0.7 behavior and evidence

0.7 adds bounded working context, readable grouped activity, connection retries, saved-task recovery, supported background CPU/network work and local attention notifications. It also adds selected Calendar/Reminders access with reviewed writes, durable question/photo/measurement cards, routed Inbox capture through the app and Siri/Shortcuts, and the Today overview.

The preceding 0.7.0 run 38113083813 passed 161 core tests and streaming UI. Baseline run 38111714194 passed 22 platform tests and the other 14 UI cases on identical production code, before the repair. That prior UI evidence is preserved in ReleaseValidation07.json and is not a claim that all 15 were repeated for 0.7.1. Real Calendar/Reminders sync, Siri routing, system background allocation and notification delivery still require phone checks. Recurring, attendee and all-day edits remain in their native apps; uncertain actions are never blindly repeated.

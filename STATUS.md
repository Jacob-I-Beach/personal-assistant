# Implementation status

**0.7.0 build 7 is verified and ready for personal signing. Installation remains user-operated and pending.** The last explicit About/version confirmation is 0.5.0 build 5 with retained chats; later screenshot feedback did not include About.

## Current evidence

The final [native validation](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38113083813) passed 161 core tests and the streaming interaction check. [Baseline run 38111714194](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38111714194) passed all 22 platform checks and the other 14 interface scenarios on identical production app code. Only a DEBUG-only streaming fixture timing changed. All 15 UI scenarios have passing coverage; this is not a claim that one final run repeated all 15. The [Release device build](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38113083813) matches source `cc5f8c432bfeb3226db6f041285e853370af9422`.

The iPhone-only package is `../PersonalAssistant-iPhone/0.7.0/PersonalAssistant-iPhone-only.ipa`, 20,845,970 bytes, SHA-256 `67a19714a6f654aee9dffd9cf36a3d46754fd8fd1949140f0aed161fcb1077eb`. Package inspection checks the physical ARM64/iOS binary, dependency pins, Metal assets, Siri action/entity metadata, privacy/background configuration, matching iPhone executables in both archives, and absence of debug backends.

## Release behavior

0.7 adds bounded working context, readable grouped activity, visible connection retries, correct saved-task cards, continued background CPU/network requests and local attention notifications. The expanded batch adds selected Calendar/Reminders sources, availability checks and reviewed version-checked writes, durable question cards with photo/measurement inputs, routed Inbox capture through the app and Siri/Shortcuts, and Today/Needs-you/Continue/recent outputs on Home.

Real Calendar/Reminders permissions and synchronization, Siri routing, background resource grants and notification delivery still require phone evidence. Native workflow rehearsals use synthetic data and are excluded from Release. Recurring/attendee/all-day event changes and custom reminder alert changes remain in their native apps. Save-only capture invokes no model. User Stop prevents automatic continuation; uncertain external actions are not blindly repeated. A full Share extension, future model scheduler and background GPU execution are outside this batch.

See [scope](Documentation/RELEASE_07.md), [evidence](Documentation/ReleaseValidation07.json) and [native screenshots](Documentation/Screenshots/0.7.0/README.md). Preserve the installed app and update with the same iLoader account. Earlier packages remain available; this is not a promise of downgrade compatibility.

## Validation budget

New hosted validation uses an estimated **USD 11.656**, leaving **USD 1.024** of the USD 12.68 allowance Jacob provided. Every job remains capped at 20 minutes; recorded rounded job durations include failures and cancellations. This is a compute estimate, not an invoice.

## Historical 0.2 installation

The verified 0.2 package and screenshots remain available. The initial installation attempt encountered HTTP 502 from SideStore's .io anisette service. Jacob selected the official SideStore (.app) preset and signed out/back in inside iLoader so the new session used it; he then confirmed that 0.2 opened. No account credentials or personal screenshots were committed to the repository.

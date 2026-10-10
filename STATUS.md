# Implementation status

**0.6.0 build 6 is verified and ready for personal signing in iLoader.** The last user-confirmed installed version remains 0.5.0 build 5, with previous chats present. Installation and physical checks of 0.6 await Jacob.

## Current evidence

[Native validation 38089667633](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38089667633) passed **138 core tests, 18 native platform tests and 2 interface scenarios** on the final source. [Device build 38089667633](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38089667633) produced the Release iPhone and Watch targets from that same source, verified through Git. Build source: `e830dabf7d6e060e3787088b13a856f03fa66432`. Synthetic test backends are excluded from the Release executable. 6 other interface scenarios have passing evidence from [run 38088741064](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38088741064), source `aa30c5095bf087afec27f9c921fa83d5b517c49d`. 5 other interface scenarios have passing evidence from [run 38087030482](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38087030482), source `b3dbbc972e58a4875f1c964693fd10c85fa04c1c`. The final production app code is unchanged from the preceding interaction run; only the synthetic streaming fixture and its assertions were adjusted. All 13 interface scenarios have passing coverage across the identified revisions. This is not a claim that a single final-source run repeated all 13.

The installable input for the existing iLoader route is `../PersonalAssistant-iPhone/0.6.0/PersonalAssistant-iPhone-only.ipa`, 20,386,691 bytes, SHA-256 `9cb0e363f877ec2731bec8960c66cd10942eb9584451d8457bb6d9b22908fee1`. Both archives have the same physical-iPhone executable; the complete archive retains its compiled Watch companion. [Native screenshots](Documentation/Screenshots/0.6.0/README.md) contain synthetic fixture data.

## Changes and practical limits

0.6 adds smooth bottom-follow with manual detachment/reattachment, top-based reading anchors, swipe-only keyboard dismissal, aligned compact live-tool rows, readable receipts, automatic memory with source/revision/history/undo, recent-chat browsing, durable reply and action receipts, foreground interruption recovery, an in-chat route preview with a separate Maps action, and useful home actions/context. The prompt remains concise; actual runtime tools and permissions provide self-knowledge. See [release scope](Documentation/RELEASE_06.md).

Location context can reuse foreground permission. Optional home weather uses a selected city or a coarse foreground area with Open-Meteo attribution. It does not enable continuous background tracking. User Stop prevents auto-resume; uncertain external outcomes are not proof of completion. The durable record tracks assistant turns, not a scheduler or independent project agent.

Native tests cover the repaired interactions, including an actual simulator background/return cycle. Real connected-model network interruptions, MapKit routing, location/weather permission behavior, larger conversations and LiDAR accuracy still need phone evidence. Preserve the installed app and data when updating. The prior packages remain available, but database migrations are not a promise of downgrade compatibility.

## Installation and budget

Use the same iLoader Apple account and the iPhone-only package. Signing, authentication and phone steps remain user-operated. This profile gates unprovisioned HealthKit and excludes Watch installation; direct PCC still requires the app entitlement.

Recorded hosted-Mac usage: 321 rounded minutes, estimated **USD 19.902 if fully billable**, within the approved **USD 20 total** compute ceiling. Failed runs are included. This is a conservative compute estimate, not an invoice; allowance/discounts and storage are separate. Each run remains capped at 20 minutes.

## Historical 0.2 installation

The verified 0.2 package and screenshots remain available. The initial installation attempt encountered HTTP 502 from SideStore's .io anisette service. Jacob selected the official SideStore (.app) preset and signed out/back in inside iLoader so the new session used it; he then confirmed that 0.2 opened. No account credentials or personal screenshots were committed to the repository.

# Implementation status

**0.5.0 build 5 is installed and opens on Jacob's iPhone, with previous chats present.** Jacob confirmed the version and retained history on October 10, 2026. The supplied package was built from source `c8855c12341ec73241333c285fb12db81d0cb109`. [Device evidence](Documentation/DeviceValidation05.json) distinguishes this confirmation from the remaining functional phone checks. The previous packages remain available.

## Current evidence

[Native run 38062830456](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38062830456), source `c8855c12341ec73241333c285fb12db81d0cb109`, passed **119 core tests, 15 native platform tests and 9 interface scenarios**, then built the Release iPhone and Watch targets. The final app source was validated in a full run. The shared suite also passed on Windows. Tests use synthetic local fixtures and do not make paid model requests.

The verified input for the existing iLoader route is `../PersonalAssistant-iPhone/0.5.0/PersonalAssistant-iPhone-only.ipa`, 19,990,620 bytes, SHA-256 `fb9cc533223697d04a5d274e0b029fb2473b85b12bba97d4787c523224500f03`. Full and phone-only archives have the same iPhone executable; the complete Watch archive and validation receipts are retained beside it. [Screenshots](Documentation/Screenshots/0.5.0/README.md) use synthetic data.

## Changes and limits

This release reworks chat position tracking and keyboard dismissal; makes tool rows compact and assistant prose normal contrast; moves thinking effort into the requested circular composer control; places user actions/attachments outside the text bubble; and removes inserted text from attachment-only sends. Images open in a zoomable viewer.

Edit/regenerate removes later messages, provider context, generated working context and title leakage from model retrieval. Existing Library files and external side effects are preserved. Cancel restores the old unsent draft.

Saved depth supports point inspection and approximate calibrated separation, with confidence/mixed-depth limits and capture timestamps. Selected points can accompany the image without becoming user-authored prose. Native working surfaces support metrics, charts, tables, comparisons, checklists, timelines and bounded scenarios. Saved selections/inputs enter the next authorized model request; they do not execute external actions or grant permission. Memory now distinguishes lifecycle, kind, source and confirmation while keeping existing scope controls.

See [RELEASE_05.md](Documentation/RELEASE_05.md) and [DEVICE_VALIDATION.md](Documentation/DEVICE_VALIDATION.md). Real-phone scrolling, larger conversations, live model behavior and LiDAR accuracy still need physical checks. Inbox routing, Share extension, scheduling and a separate persistent task ledger remain follow-on design work.

## Installation and budget

Keep the existing app installed and use the same iLoader account. GUI and authentication remain user-operated. The iPhone-only route still excludes Watch deployment and gates unprovisioned HealthKit; direct PCC requires the app entitlement. Neither compilation nor private sideloading grants those capabilities.

Recorded hosted-Mac usage totals 256 rounded minutes, estimated **USD 15.872 if fully billable**, within the authorized **USD 16 total** ceiling. Failed/cancelled execution is included; confirmed startup rejections with no runner consume zero runner minutes. This is not an account invoice. The October 10 billing snapshot showed USD 12.00 gross compute fully discounted and zero net billed compute, but reporting may lag later jobs. Preserve the conservative ceiling; taxes and future storage are separate. Full jobs remain capped at 20 minutes.

## Historical 0.2 installation

The verified 0.2 package and screenshots remain available. The initial installation attempt encountered HTTP 502 from SideStore's .io anisette service. Jacob selected the official SideStore (.app) preset and signed out/back in inside iLoader so the new session used it; he then confirmed that 0.2 opened. No account credentials or personal screenshots were committed to the repository.

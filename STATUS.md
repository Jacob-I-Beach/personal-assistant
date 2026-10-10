# Implementation status

## Current 0.3 release

**Jacob reports that 0.3.0 build 3 opens on his iPhone and his previous chats are present.** The in-place iLoader update is confirmed by that report. Live-model regression checks are now underway.

Source 6b0ba6ba51b22df7c3821d6b53e4c4607a31da6c passed [native validation 38016040142](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38016040142): **75 macOS core tests, eight iOS platform tests, four interface tests, and the iPhone/Watch Release build**. Shared-core tests also pass on Windows. Fourteen native simulator screenshots are retained in [Screenshots/0.3.0](Documentation/Screenshots/0.3.0/README.md). The latest sidebar, Library, attached file and rendered PDF were visually inspected. The interface test creates a folder, archives/restores a chat, deletes a disposable chat, attaches a saved CSV, previews a generated PDF and returns to the file view. This is selected coverage, not a complete accessibility or hardware audit.

The verified installation input is **../PersonalAssistant-iPhone/0.3.0/PersonalAssistant-iPhone-only.ipa**, 13,980,729 bytes, SHA-256 **888656b529fdc98aeea1c2921f6cb9e3b4695c00c9496de22a4489766d75b00b**. It is a physical ARM64 iOS 27 build with Metal kernels, ten catalog entries and no downloaded model weights or Apple provisioning profile. The full Watch-containing archive, executable-identity comparison, checksums and build provenance are retained beside it.

## What changed

- ChatGPT-primary onboarding and a fresh conversation on cold launch; deliberate continuation through a slide-out sidebar.
- Folders with optional instructions; rename, move, archive, restore and confirmed deletion.
- Files and Library in the attachment menu; per-message playback and voice settings.
- Preserved originals, scoped workspace search, native file preview/share, bounded PDF/Office/text extraction, OpenAI original-file inputs, and real paginated PDF output.
- Public plans, understandable execution receipts, source links and durable error messages; corrected sparse/final-only/refusal response handling.
- Plain JSON JavaScript returns, explicit tool success/failure and blocked fabricated follow-up files after failed calculations.
- Device resources, reviewed foreground location, calendar/message composers, and reviewed Maps/Phone handoff.
- Ten pinned MLX packages across Qwen, IBM Granite, Liquid, SmolLM and Gemma; upstream model configuration retained, working-memory estimates labeled and hardware performance unmeasured.

Details are in [RELEASE_03.md](Documentation/RELEASE_03.md) and [OPERATING_BEHAVIOR.md](Documentation/OPERATING_BEHAVIOR.md).

## Live evidence and remaining checks

Jacob confirmed 0.2 installation and launch, ChatGPT authorization, account-model loading and a simple live reply. His Apple-model screenshot showed correct addition code rejected for returning an array, followed by an invented 61.55 total saved as JSON under a CSV filename. Tests now reproduce that code yielding **60.5**, allow its return shape, and guard failure-to-file recovery.

GPT 6.1 Sol also stopped without an answer on image/depth and text-only Jupiter requests. The source had a confirmed defect discarding completed tool calls when the terminal response contained an empty output list. That defect is corrected and tested, and genuinely blank completion becomes a persisted visible failure. A live 0.3 Jupiter retest is pending after the confirmed update.

Native actions, camera/depth, dictation, web-search account policy and local model loading/speed/heat still need physical-device checks. CI uses synthetic fixtures and no paid external model inference. AppIntents SSU archive diagnostics remain nonfatal; actual Siri/Shortcuts discovery is not established by the build. Existing voice-session deprecation/main-thread warnings remain recorded for follow-up.

## Installation and spending

Use the same iLoader account and keep the existing app installed. See [DEVICE_VALIDATION.md](Documentation/DEVICE_VALIDATION.md). GUI, authentication and phone prompts remain user-operated; no computer-use automation is authorized.

Official iLoader 2.3.6 does not provision this app's Watch companion or request HealthKit. The iPhone-only deployment gates Health off before authorization/querying. Watch's compiled archive is retained for a compatible signing route. Direct PCC still requires this app's approved entitlement.

Jacob explicitly raised the total hosted-Mac budget to **$10**. The 16 completed jobs total **139 rounded minutes**, an estimated **USD 8.618 if fully billable** at $0.062/minute. This includes failed and cancelled jobs. It is not an account invoice; included allowance, tax and separate artifact storage are not established. Evidence is in [BuildValidation.json](Documentation/BuildValidation.json).

## Historical 0.2 installation

The verified 0.2 package and screenshots remain available. The initial installation attempt encountered HTTP 502 from SideStore's .io anisette service. Jacob selected the official SideStore (.app) preset and signed out/back in inside iLoader so the new session used it; he then confirmed that 0.2 opened. No account credentials or personal screenshots were committed to the repository.

# Implementation status

**0.4.0 build 4 is verified and ready for personal signing and installation.** Source `d8af8e22bc6317101d8186f3e367c0840014f195`. The latest user-confirmed installation is still 0.3.0 build 3, with prior chats intact. Jacob confirmed that its GPT 6.1 Sol Jupiter response worked well with web sources and JavaScript. The 0.4 batch addresses his presentation screenshots and the later workspace requests together.

## Current release evidence

**97 shared-core tests, 14 native platform tests, seven interface scenarios across two runs, and the physical iPhone/Watch Release build.** [Final run 38028597942](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38028597942) reran all core/platform tests and the export interface scenario. The other six interface scenarios passed in [run 38027478506](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38027478506); Git object comparisons verify identical App, Sources, project, package manifest and dependency contents. That earlier run failed only its export-dismissal gesture. The final test successfully saved through the native picker and separately verified cancellation. The 97-test shared suite also passed on Windows. No paid model calls or personal captures were used.

The verified iPhone-only IPA is `../PersonalAssistant-iPhone/0.4.0/PersonalAssistant-iPhone-only.ipa`, 19,708,149 bytes, SHA-256 `a8cc8e34131cfdd067096430b62071d5314ceeb9834184574c932b689b0c5217`. Inspection confirmed ARM64 physical iOS 27 code, Metal libraries, native math resources/licenses, 20 pinned dependencies and Files configuration. The full Watch-containing archive, byte-identical iPhone executable comparison, checksums, provenance and FeatureValidation.json are retained beside it. [Native captures](Documentation/Screenshots/0.4.0/README.md) use synthetic content only.

## What changed

- Public updates remain separate; response actions appear at the end. Web activity persists, JavaScript results are readable, and equations render natively.
- More than three unique source URLs collapse into a source panel, preserving citation references.
- Supported GPT models expose Low, Medium, High, Extra High and Max effort, remembered per model and wired to exact provider values.
- New chats can receive bounded, model-generated topic names. Manual names and protected-context boundaries are preserved; the setting is optional.
- Photo library opens from the persistent chat view, with cancellable, conversation-bound import.
- Generated artifacts and PDFs receive verified Files-visible copies; native export reports completion or cancellation accurately.
- Connected folders support scoped bookmarks, per-chat/model/editing access, listing, reading, bounded search, creation and reviewed version-aware text edits with recoverable original snapshots.
- A compact base prompt and runtime capability query describe the real tool environment. Existing providers, history, memory, sandbox, PDF pipeline and native integrations are reused.

See [RELEASE_04.md](Documentation/RELEASE_04.md) for scope and [DEVICE_VALIDATION.md](Documentation/DEVICE_VALIDATION.md) for focused phone checks.

## Remaining real-device evidence

Live semantic-title quality, the thinking control against Jacob's account models, real Photos import/vision, the earlier image/depth response, security-scoped provider access after relaunch/revocation, location/native composers, and local-model memory/speed/heat still require phone checks. The simulator establishes native picker presentation and actual local export, not iCloud synchronization or all document-provider behavior.

The earlier empty-output transport defect and plain-array JavaScript result rejection are covered by regression tests. The tested sum is 60.5; failed calculations cannot be followed by a fabricated file save. A model still needs live task-quality evaluation.

## Installation and spending

Use the same iLoader account and keep the existing app installed. GUI, authentication and phone prompts are user-operated; computer-use automation is not authorized. Official iLoader 2.3.6 does not provision this app's Watch target or HealthKit. Health is gated off before authorization/querying in this profile. The full compiled Watch archive remains available for a compatible signing route. Direct PCC requires this app's entitlement.

The 21 recorded jobs total **189 rounded minutes**, estimated **USD 11.718 if fully billable**, within the authorized **USD 12** ceiling. The estimate includes failed and cancelled jobs at USD 0.062/minute; it is not an account invoice. Included allowance, taxes and separate artifact storage are not established. Full jobs have a 20-minute cap; the final focused run used a 15-minute cap. Check the remaining budget before any new run. [Ledger](Documentation/BuildValidation.json).

No remote shell/Python service, share extension, perpetual background agent, unrestricted iOS control or binary Office/PDF editing was added. Existing nonfatal App Intents discovery and voice-session warnings do not establish physical Siri/voice behavior.

## Historical 0.2 installation

The verified 0.2 package and screenshots remain available. The initial installation attempt encountered HTTP 502 from SideStore's .io anisette service. Jacob selected the official SideStore (.app) preset and signed out/back in inside iLoader so the new session used it; he then confirmed that 0.2 opened. No account credentials or personal screenshots were committed to the repository.

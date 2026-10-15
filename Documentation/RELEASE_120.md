# Personal Assistant 1.2.0 — build 23

This release completes the remaining feasible implementation from both supplied audits. The item-by-item record covers 18 code findings, seven code watchlist items and 32 product recommendations; the journey map records all 28 proposed acceptance scenarios without representing physical or human tests as automated results.

## Added

- Direct project creation from an empty project or existing chat, editable goals/decisions/questions, current output links and an unsent Continue action.
- Retained transcript/output snapshots before editing, inspectable conversation history and explicit restore. Restoring preserves current access revocations and never restarts old actions.
- Versioned personal-work archives with coverage/exclusion review, integrity/identity/path checks, isolated restore and a next-launch library selection. Existing libraries remain available; account credential stores, model weights and execution queues are excluded.
- Inbox search, Unhandled/Filed filters, timestamps, chat/project movement and recoverable removal.
- Separate memory unload, derived-cache removal and model/partial-package removal with an owned-path boundary and measured file bytes.

## Changed

- Saved chats can be read while the original response continues. Return and Stop remain bound to that response; browsing never replaces its execution context or draft.
- Root sheets use a typed presentation owner. Native reviews wait for the real dismissal and cannot replace an open review or discard an editor unexpectedly. Sidebar destinations remain reachable when text is large, and opening history dismisses the composer keyboard.
- Readiness distinguishes account, catalog, selected model, memory fit and individual computer services. Task strips, recovery states, output identities and source-reference drafts use shared representations.
- Library has an incremental search index, excerpts and filename/type/date/origin filters. Chat search distinguishes title hits, exact content hits and related-word fallback. Memory exposes its retained source and uncertainty.
- Scenarios use exact locale-aware values with the same step validation as sliders; undo/reset and explicit conflict recovery are local edits. Charts expose all selected series, symbols and a data table. Photos retain accessible normalized point selections.
- Settings are grouped, routine preferences commit through validation, and structured forms retain explicit Apply/Cancel semantics.
- Response bodies and streamed chunks have bounded app-owned buffers. Async transfers retain the configured certificate pin and redirect refusal. Browser workspaces have an idle lifetime, resource ceiling and bounded observed controls.
- Transcript checkpoints skip unchanged encoding/SQL; a 5,000-message/1,000-document fixture separates checkpoint, retrieval and request-assembly timings. Results are PC/Mac fixture measurements, not phone performance claims.
- Swift and JavaScript consume shared argument/receipt fixtures. Retained Health-derived revisions continue to block ordinary device backup after editing and reopening.

## Removed

- The requirement to stop a response just to read another saved chat.
- Destructive transcript truncation without a retained prior version.
- Generic retry suggestions for uncertain action receipts.
- Filename-only output assumptions, the six-output discovery cap, and repeated full payload encoding during an unchanged cached checkpoint.

## Verified

- 265 shared-core tests on Windows and Mac; 70 companion tests; seven updater checks.
- 34 native platform/transport checks, including exact certificate pin acceptance/rejection and redirect protection.
- 21 native UI journeys. A timing-limited interaction job was rerun in smaller groups against the same compiled app; its assertions were preserved and the compound scenario received a 180-second test allowance.
- Real isolated Python processing of a synthetic CSV into a checked workbook and rendered PDF; real Edge inspection/action review; rendered control-center review/file/download/reload behavior.
- The installed PC companion is 1.2.0 release r1. Its account, one pairing, 28 task identities, certificate, data folder and sign-in startup were preserved after an idle update and encrypted task-database backup. A fresh non-inference check returned eight models, selected-model availability, Python readiness and pinned private HTTPS200.

## Still pending

The user must sign/install the phone package in place and verify the real device. The memory profile grant, sustained 64K local inference, actual audio/depth/VoiceOver and extended lock/network transitions remain physical checks. Health and external notifications/Live Activities remain deliberately deferred pending Apple Developer provisioning. Live answer-quality evaluation and a human usability session were not replaced by synthetic fixtures. No live model prompt, personal message send, calendar write or Health read was used for this validation.

The Standard and Memory packages contain the same compiled app. The Memory variant requests the regular increased-memory entitlement; it does not itself grant memory or establish that 64K fits the physical phone.

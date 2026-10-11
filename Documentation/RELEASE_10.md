# 1.0 — completing everyday work

Status: development. This is an implementation scope and evidence ledger, not a completed-feature claim. Preserve the installed app, chats, signing identity, and all 0.9 packages.

## Direct defects to repair

- Health Connect selected data aborts in HealthKit authorization validation. Three 0.9 device reports establish this call path. Correlations need authorization of their component samples; resolvable catalog types are not necessarily valid direct authorization inputs. Keep pending selections through a failed request and contain Objective-C framework exceptions at the authorization boundary.
- Background failures require a host that owns the work independently of the phone. Sign in with ChatGPT currently rejects the Responses `background` field. The existing phone-side continued-processing task is not a server worker. Host preference has been requested; do not silently switch accounts or introduce paid API usage.
- Older 0.8 device reports establish an additional notification-response callback crash in UIKit state restoration. Replace the async delegate bridge with an explicit, main-thread completion path and retain task routing.
- Short user messages and attachments need a shared trailing edge. The attachment scroller's expanded width and leading alignment must not center the visible contents.
- Apple model tool calls need schemas and argument handling that match the same tools used by connected models. Fix the observed format failure and test a representative location/place workflow without a live model call.
- Home context must refresh while Home is visible and on foreground return. Keep observation and retrieval timestamps honest; use a short contextual greeting grounded in available task, planning, date and weather information.

## 1.0 workflow priorities

1. Communications: contact lookup and explicit disambiguation; reviewed messages and attachment handoff; distinguish sent/queued, cancelled, failed and unknown. Add native email composition and direct output sharing where the platform supports them.
2. Computation and documents: authorized file inputs, useful parsing/statistics, configurable bounded execution, intermediate work, faithful document/page inspection, richer deliverables and inspection of generated results. A larger memory number alone is insufficient.
3. Maintained work: update artifacts and native surfaces by stable ID and expected version; keep revision history; link authoritative outputs, decisions and unresolved questions to a project; provide an explicit return from surface changes to the assistant.
4. Planning: recurring and all-day commitments, reviewed deletion, related-change review with individual outcomes, and execution-time version/permission checks.
5. Discovery and tool contracts: permission-aware combined search, native parameter types, current tool discovery instructions, stable source references and useful coverage reporting.
6. Continuity: resumable task ownership outside the phone where configured, bounded scheduling and clear waiting-for-device/approval states. Phone tools still require a phone; cancellation and unknown external outcomes must not be replayed blindly.

## Earlier proposals being reviewed

Share extension/system entry points, reusable procedures, native voice, project workspaces, offline packs and a clearer connection dashboard are relevant. Mailbox providers, bookings, arbitrary browser automation, HomeKit, NFC, RoomPlan and specialized physical-object records require a concrete integration or use case; they are not implied by adding generic tool names. Record the final decisions and actual delivery in this file before packaging.

## Validation and handoff

Use synthetic core/provider tests for logic, native checks for framework boundaries and changed interfaces, and real screenshots for visual claims. Do not run paid model calls, send messages, create real appointments, or read Health records for tests. Raw phone reports stay outside Git. The final handoff must contain Added / Changed / Removed / Still pending and must distinguish implemented source, native evidence and phone-confirmed behavior.

Primary references: [ChatGPT connection limits](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations), [HealthKit correlation authorization](https://developer.apple.com/documentation/healthkit/hkcorrelationquery), [cloud task execution](https://help.openai.com/en/articles/20001280-using-cloud-browser-in-chatgpt).

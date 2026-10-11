# 1.0 — completing everyday work

Status: integration and packaging. Version 1.0.0, build 11. Preserve the installed app, chats, signing identity, and all 0.9 packages. The sections below distinguish implemented source from device acceptance.

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

## Implemented in this batch

- All six direct repair paths above. The Health/callback/alignment/Home/tool-schema foundation passed native validation at source `10015ef`.
- A Windows companion owns encrypted, durable, device-scoped jobs, cursored progress, file snapshots and per-operation outcomes. Reconnecting rebuilds the same transcript; Stop is distinct from disconnect. Phone-only tools keep their existing execution-time permissions and native reviews. The companion uses its own supported ChatGPT plan authorization, with no API-key fallback or copied credentials.
- Native Computer pairing by QR or a supplied connection code, pinned TLS, a revocable device credential, correct chat return routing and a real Lock Screen/Dynamic Island extension. Stale activity is labeled; the system's continued-processing failure banner is not used to represent computer-owned work.
- Actual isolated Python with pinned numerical/document libraries, input file handles, JSON intermediate state, rich document output, formula/cache inspection and rendered document pages returned as image evidence. Original document/dataset bytes travel to the computer workspace by handle instead of being embedded in model input; another permitted Library file can be transferred during work. Large tool results use context excerpts with exact receipt retrieval. Real CSV → workbook/PDF → reopened/rendered output was exercised on this PC. Inspection intermediates remain evidence on the PC; requested artifacts appear in the phone Library.
- Contacts search within iOS-granted access; reviewed native email, message attachments and file sharing. Native callbacks distinguish sent, saved draft, cancelled and failed. No delivery/read claim or automatic message retry.
- Stable text-document IDs, expected-revision updates and exact patches, inspectable/restoreable history. Files copies update only if they still match the prior content. Surfaces can be revised in place while preserving compatible selections, and selections have an explicit conversation follow-up.
- A project record links the goal, decisions, open questions and authoritative output IDs; topic-folder chats can share it under existing data rules. Library has a Projects entry. `search_context` combines existing permitted app searches with explicit coverage and exclusions.
- Recurring and all-day planning, explicit occurrence/series scope, reviewed removal and one review for related changes with saved per-item outcomes. Recurring events with attendees remain managed in Calendar.
- Reviewed PC schedules: once/daily/weekly, at most 30 occurrences within 90 days, ten minutes and twelve steps per occurrence. Unattended runs are research/drafting only; they do not send communications, modify phone data or create more schedules. Missed work is recorded without a catch-up burst. Native controls show schedules and task results.

## Deliberate follow-ons and limits

- Actual account authorization, in-place iPhone install, Health access and a real selected-model background task remain user-operated device acceptance steps. Synthetic inference is used for automated checks.
- Sustained APNs notification/Live Activity delivery while the phone app is fully suspended is not provisioned in the free-signing route. This does not stop the PC job. The displayed activity has a stale state and catches up on connection. A private VPN route is needed away from the home LAN; it is not silently installed or authenticated.
- A Share extension, full interruptible voice conversation, mailbox reading, service bookings, HomeKit/NFC/RoomPlan, an arbitrary browser operator and general phone UI control are follow-ons. Existing Siri/Shortcuts captures and dictation remain available. Text-document revisions ship; rich binary-document revision history is not presented as a finished phone editor.
- For the later Home Screen question: pymobiledevice3 exposes layout reading and a legacy setter, but that does not verify writes on this iOS version. Apple Configurator documents Home Screen layout changes on Mac. A Windows device-control layer needs separate on-device verification; none was added or exercised against the user's Home Screen. References: [pymobiledevice3 implementation](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/springboard.py), [Apple Configurator](https://support.apple.com/en-au/guide/apple-configurator-mac/cadbf9c2a0/mac).

## Validation and handoff

Use synthetic core/provider tests for logic, native checks for framework boundaries and changed interfaces, and real screenshots for visual claims. Do not run paid model calls, send messages, create real appointments, or read Health records for tests. Raw phone reports stay outside Git. The final handoff must contain Added / Changed / Removed / Still pending and must distinguish implemented source, native evidence and phone-confirmed behavior.

Primary references: [ChatGPT connection limits](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations), [HealthKit correlation authorization](https://developer.apple.com/documentation/healthkit/hkcorrelationquery), [cloud task execution](https://help.openai.com/en/articles/20001280-using-cloud-browser-in-chatgpt).

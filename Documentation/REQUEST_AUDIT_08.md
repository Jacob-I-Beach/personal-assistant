# Request-to-implementation audit: 0.8

Audited October 11, 2026 against the packaged app source `287f4b2e18d9e5a14a724f8e27bf23afc9f6bf15`, the preceding 0.6/0.7 work, native evidence and the user's reports. The 0.8 phone installation remains unconfirmed. Source implementation, simulator evidence and a successful real-world outcome are separate statuses.

The 0.8 work primarily implemented the concrete interaction defects and added background/Health support work. It did not implement every proposed capability in the supplied assistant conversations. The previous handoff did not make that boundary prominent enough.

## Direct requests in the latest paragraphs and five screenshots

| Request | Actual work | Status and remaining limit |
| --- | --- | --- |
| Continue GPT work after going Home | Report actual incoming network and tool-result bytes before visible answer text; correct scheduler submission/callback handling; preserve task-specific lifecycle diagnostics. | Implemented support changes, but the reported one-second failure has **not yet been demonstrated fixed on the phone**. The original filtered trace did not establish its exact cause. No remote worker was added. |
| Expanded activity, swipe to compact Dynamic Island, tap to expand | Uses the system activity supplied by continued processing. | **Partial.** No custom ActivityKit/WidgetKit extension or bespoke island layout/interaction was built. The desired physical interaction remains unverified. |
| Attention notifications that explain and return to the task | Existing local attention notifications describe reply readiness, review or interrupted work and route taps to the conversation. | Added in 0.7, not new in 0.8. This is local notification delivery, not a server/APNs execution system. Delivery on this installation remains unconfirmed. |
| Jump-to-latest button | Corrected active scroll-controller ownership and immediate jump/layout behavior; latest content stays above the composer. | Implemented; native platform and interface checks pass. |
| Expanding tools must preserve reading position | Keep the real content offset when a disclosure changes; maintain temporary collapse space to prevent upward clamping. | Implemented. Native evidence records the web heading at the same vertical coordinate before/open/closed; nested tool and latest-jump checks also pass. |
| Model-specific working context up to 1,000,000 | Added per-model/account selection, advertised-limit precedence, known-model limits, output reserve and application to request planning. | Implemented, with an **approximate** text/token planner. Provider/account limits remain authoritative; this is not an exact tokenizer or a promise every input fits. |
| Remove top-right New Chat and menu New Conversation/Settings | Removed those duplicates; New Chat and Settings remain in the sidebar. | Implemented and checked in native UI. |
| Copy/share feedback and larger Edit control | Shared press style, copy checkmark and accessibility announcement; equal 44-point action frames and 16-point symbols; share/edit feedback. | Implemented in the message actions. Actual phone feel remains unreviewed. |
| Gentle, varied haptics, including a triple question cue | Selection, light send/save, soft copy/first reply and three soft question taps; foreground and rate-limit guards; preference to disable. | Implemented for core chat controls, disclosures and main Settings controls. This was **not an exhaustive redesign of feedback on every screen**. |
| Plus-menu Library should open the real Library | All Library routes use the shared destination; attaching a Library file returns it to the active conversation. Also fixed a missing navigation environment that caused an attachment crash. | Implemented; Library/attachment native scenario passes. A separate connected-folder/export test remains pending after its startup readiness correction. |
| Coherent organization and discoverable capabilities | Added Connections and aligned sidebar/Home/Library routes and descriptions. | **Partial product reorganization.** No complete information-architecture redesign or unified project workspace was built. |
| Model understands the surrounding app without rediscovering it | Compact app-authored navigation/capability/settings orientation is sent through the normal engine and counted in the context budget; exact tools remain discoverable. | Implemented. Includes actual feature availability/preferences without copying all personal records into every request. |
| Correct Health connection | Separate Health-enabled signing input, installed-profile capability gate, and a narrowly patched local signing helper. Existing Health reader covers seven days of steps, recorded sleep and workouts. | **Not yet complete end to end.** The first helper was packaged incorrectly. Revision 2 fixes the loader interface and the user confirmed it opens; actual Apple provisioning, installed entitlement and Health authorization/overview remain pending. This is not unrestricted Health database access. |
| Full-width multiline composer | Text spans the input width, with controls in a separate row; transcript and composer have distinct layout space. | Implemented; native screenshot and width/keyboard check pass. |
| Remove the repeated ordinary GPT consent popup | Normal Send authorizes the selected connection; optional confirmation preference remains; explicit revocation and Health sharing remain distinct. | Implemented; immediate-send native check passes. |
| Visually distinguish nested disclosures | Added indentation, leading rules, group backgrounds, larger heading interaction and stable anchors. | Implemented; inspected native screenshots. |
| Make expanded tool details comfortable and human-readable | Markdown rendering, result titles before body, primary-contrast prose, fewer internal fields, single-result unwrapping, and raw data kept behind diagnostic copying. | Implemented shared presentation improvements. Not a separate custom-designed result screen for every possible tool. |
| Constant relevant personal context/location from the earlier request | Persistent opt-in for relevant foreground location requests and optional coarse-location/city weather. | **Only partial.** No Always-location permission, continuous background location stream or general ambient data collection was added. |

Key implementation: [RootView](../App/Views/RootView.swift), [scroll controller](../App/Views/StableChatScrollView.swift), [disclosures](../App/Views/AssistantDisclosure.swift), [feedback](../App/Views/AppFeedback.swift), [Connections](../App/Views/ConnectionsView.swift), [context controls](../App/Models/ContextWindowSettings.swift), [model budget](../Sources/AssistantCore/ModelContextBudget.swift), [app orientation](../Sources/AssistantCore/AssistantAppContext.swift), [background window](../App/Device/ResponseCompletionWindow.swift), [Health reader](../App/Health/HealthOverviewService.swift).

## Earlier requests already addressed before 0.8

These are part of the current app but must not be counted as new features from the latest four-hour block.

- **Automatic memory with history and undo:** 0.6 added source-linked automatic creation, version-aware updates, forgetting, tentative inference, expiry and user undo. Original chats and memory are separate records.
- **Saved work and outcome receipts:** 0.6 added durable turns/checkpoints and recovery using saved action results. Unknown external outcomes are not blindly retried; Stop is distinct from interruption.
- **Maps preparation:** 0.6 added place/route preparation and an in-chat preview, with opening Apple Maps as a separate user action. Opening Maps is not proof navigation began.
- **Context exhaustion and ineffective Continue:** 0.7 reduced request-only tool observations while retaining complete stored evidence and tool/result consistency, prevented recursive retrieval of old tool JSON, and stopped offering ineffective retries for unsupported oversized requests. 0.8 additionally exposes a real model budget adjustment.
- **Crowded tool usage and stale Continue cards:** 0.7 grouped consecutive activity and related operations, superseded old unfinished requests and limited the card to eligible current work. 0.8 further improved hierarchy and readable results.
- **Visible reconnect attempts:** 0.7 added up to five retries for eligible temporary transport failures, with visible attempt state and preserved completed tool receipts. Authentication, invalid input, quota and user cancellation are not blindly retried.
- **Calendar and Reminders:** 0.7 added selected-source reads, bounded availability, reviewed create/update/completion and fresh version/read-back checks. Recurrence, multi-person scheduling, all-day-series edits and arbitrary deletion are not claimed. The 0.7.1 EventKit callback crash was separately repaired and the user confirmed Save/reopening with retained chats.
- **Evidence requests:** 0.7 added task-bound text/choice/photo/measurement questions, skip/later and continuation from the answer.
- **Capture/inbox/system entry:** 0.7 added save-only/for-later/answer-now inbox handling and Siri/Shortcuts intents that target a chat. It did not add a Share extension.
- **Today and task diagnostics:** 0.7 added actual selected-calendar/reminder context, pending questions, resumable work, recent outputs and a scoped task diagnostic report. Synthetic rehearsal scenarios are developer tests, not a user-facing rehearsal mode.

See [0.6 scope](RELEASE_06.md), [0.7 scope](RELEASE_07.md), and [0.7.1 phone evidence](DeviceValidation071.json).

## Decisions on the large capability and product-design conversations

| Idea family | Actual disposition |
| --- | --- |
| Contacts, people lookup, aliases and disambiguation | Worthwhile follow-on; **not implemented**. No ability to resolve a person's name into a contact was added. |
| Shared references across people, places, files and events | Local records already have stable identifiers; a general cross-service entity/resolution layer was **not built**. |
| Share extension; capture from other apps | Worthwhile follow-on; **not implemented**. In-app capture/file import and Siri/Shortcuts inbox routing exist. |
| Email composer, attachments and mailbox connectors | Worthwhile follow-on; **not implemented**. Native artifact sharing already exists; no inbox access or email sending tool was added. |
| Future triggers, recurring assistant runs and monitoring | Deferred pending a real execution host and task controls; **not implemented**. Local notifications and foreground recovery are not scheduled model execution. |
| Calendar recurrence, location-triggered reminders, multi-person availability and travel-aware scheduling | **Not implemented** by the current planning tools. Existing one-off selected-source planning is narrower. |
| Natural conversational voice, barge-in, shared voice/text state | Separate transport/interaction work; **not implemented**. Existing dictation and read-aloud are not equivalent. |
| Rich documents, native workbook/slides editing, PDF images/page reasoning and image redaction | **Not added in 0.8.** Existing extraction, original-file previews, CSV/text PDF output and native charts remain more limited. |
| Authenticated booking/account workflows and interactive browser control | **Not implemented**. No new service connectors or arbitrary cross-app control were added. |
| Python/terminal/packages/long computation | **Not implemented**. The bounded offline JavaScript sandbox remains the execution environment. |
| Persistent project workspaces across chats | Chat folders, files, memory and saved turns exist; a complete project record with dependencies, decisions and completion criteria is **not implemented**. |
| Reusable procedures, teach-me-once skills and self-extending toolbox | **Not implemented as a formal saved workflow/skill system.** Remembering a preference is not the same capability. |
| Persistent mini-tools | Native tables, charts, checklists and scenarios exist; a general reusable mini-app system with its own durable state/actions is **not implemented**. |
| Shared attention / pointing to exact content | Selected image/depth points and local file references exist; broad paragraph/cell/version selection across tools is **partial, not a complete new system**. |
| Explicit definition of done; safe changes of mind | Turn phases, revisions, message editing and receipts exist. User-visible task completion contracts and dependency-aware replanning are **not implemented** as general features. |
| Recovery and undo | Implemented for supported memory/files/workflows; no universal undo or proof of downstream delivery/call/navigation outcomes. |
| Capability/permission dashboard | Registry and Connections improve visibility; a complete per-operation connected/denied/unsupported/stale dashboard is **partial**. |
| Context freshness and contradiction detection | Memory sources/expiry/version checks exist; no general project dependency graph or automatic contradiction-review service was built. |
| Evidence drawer, diagnostics and rehearsal | Sources, tool details, saved receipts and task diagnostics exist. Rehearsal is developer-side synthetic coverage; there is no new user-facing full workflow simulator. |
| Spatial memory, object passports, RoomPlan, NFC and physical inventory | **Not implemented.** Existing camera/depth captures are narrower building blocks. |
| HomeKit, broader device coordination, widgets and Spotlight project search | **Not added in 0.8.** Existing Watch/inbox paths should not be mistaken for these broader integrations. |
| Attention modes, opportunities feed, proactive gap finding and personal experiments | **Not implemented as dedicated product features.** The model can discuss these ideas, which is different from the app supplying them. |
| Offline mission packs | Local files/captures can be retained; a verified, refresh-aware package builder is **not implemented**. |
| Local/cloud cooperation | Selected connected model, offline models and sharing restrictions exist. Automatic task routing, second-model review and a general redaction/processing policy interface were **not added**. |
| Bounded delegation | Tool permissions, resource bounds, saved work and Stop exist; a general user-defined time/resource/approval contract and unattended worker are **not implemented**. |

These were not all rejected as bad ideas. Many are useful next integrations. They were deferred rather than delivered, and the earlier handoff should have stated that directly.

## What the elapsed work accomplished, and where it went wrong

Six native build/validation cycles were run for 0.8. Repeated compilation, simulator startup, UI runs, evidence collection and corrections consumed a substantial part of the later elapsed time. Git/source evidence does not establish a precise minute-by-minute split of the full four hours, so no percentage is claimed.

Some checks exposed real app defects: a missing navigation environment caused Library attachment to crash; the composer could cover the final response; the active scroll controller could lose the jump command; and disclosure geometry shifted the reading position. Those were fixed in product code. Other iterations dealt with brittle automation selectors, startup readiness and screenshot polish. That loop was inefficient and was stopped after the user asked whether another run was needed.

The first Health helper was a separate handoff failure. A successful optimized Rust build and Health-scope unit tests did not prove the packaged GUI would load. It lacked Tauri's production custom-protocol feature and tried localhost:1420. Revision 2 enables the production feature, uses the official Tauri build command, and checks the embedded index/script/style. **The user has now confirmed the normal revision-2 loader interface opens.** Apple provisioning and app Health access remain separate, pending outcomes.

Current evidence is 173 core, eight native EventKit and 33 platform checks passing, plus 16 of 17 UI scenarios with passing coverage across the documented source revisions. The connected-folder/export scenario is pending after its test-only startup wait correction. This is not a claim of a fully green final suite or completed physical background/Health validation.

The two principal unfinished outcomes are **reliable background response continuation on the user's phone** and **actual Health access in the signed installation**. The broader product ideas above require further implementation, not additional tests of the current code.

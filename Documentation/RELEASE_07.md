# 0.7 — finishing longer tasks

Source candidate, not a verified iPhone package. The 0.6 IPA and installed data are preserved. New user evidence is five phone screenshots plus design suggestions; the screenshots do not show About, so they do not independently confirm the installed version.

## Authorized expansion

Jacob approved the four proposed additions and USD 12.68 of remaining hosted validation on October 10. That supersedes the previous USD 20 stop. The ledger preserves the old USD 19.902 estimate and separately records this incremental allowance; the arithmetic ceiling is USD 32.582, not a claim about actual GitHub billing.

- Calendar/Reminders: chosen sources, separate connected-model sharing choice, bounded schedule/reminder reads, time-zone-aware availability inside requested daily hours, reviewed creates/updates/completion, fresh version checks and read-back receipts. Recurring-series and all-day-event edits remain in the native apps. EventKit requires full OS access to read; app selection narrows what these tools use. Cloud sync, another person's availability, travel time and notification delivery are not inferred.
- Questions: one focused text/choice/photo/measurement request, free-text alternatives, skip and Later. Questions survive interruption and remain bound to the original task. Actual answers are saved as user input; they do not become new tasks or new external-action approvals. Answered photos remain authorized attachments. Older task questions cannot alter a newer request.
- Inbox: save-only, for-later and answer-now inputs with optional existing-chat destinations. Save-only invokes no model and creates no memory. Routing preserves existing drafts and never silently substitutes a missing destination. A new App Intent exposes named chat entities and handling choices to Siri/Shortcuts; it uses the current foreground app entry point. A full Share Sheet extension remains a later milestone.
- Home: real Today events/due reminders, pending questions under Needs you, continued work, an Inbox entry point and recent generated files. Tapping items opens their details or related work. Empty states offer connection/capture actions without invented schedule data.

The Calendar review and question-resume interface scenario uses a clearly synthetic provider and synthetic planning store, excluded from Release. Core tests independently verify gap computation, DST/weekend behavior, inbox permissions, deletion, question replay, skip and photo/answer continuity. Native compilation checks the EventKit/App Intents calls; live permission, sync and delivery behavior remains a phone check.

## Reproduced mechanisms and fixes

- The local planner treated the latest user turn and every accumulated tool result as indivisible. The ChatGPT route used a conservative 128,000-byte request-text budget, not the provider's token limit. Continue resent the same oversized turn. The planner now reduces request-only tool observations and removes incompatible opaque continuation state while preserving call/result pairs. If completed code arguments are too large, the entire work block becomes a clearly labeled saved-evidence record with source references. Original user text and the full database record remain unchanged. Oversized user input fails explicitly and does not offer an ineffective retry.
- History search and recent-chat browsing now return human conversation content rather than recapturing earlier tool JSON. Exact receipts remain readable by source ID. This removes a source of recursive context growth.
- Unfinished work is eligible only for its latest user request. A newer request supersedes earlier unfinished turns. The card exposes the actual reason and only offers Continue when its existing resource/resume limits permit it. Response failures no longer produce an extra blocking alert over the saved-work card.
- Network loss, incomplete transport, and selected temporary HTTP failures retry up to five times. The app shows the attempt number, resets only uncommitted output, and preserves saved tool receipts. Authorization, invalid input, quota exhaustion, output limits, and user cancellation do not use this retry loop. Long Retry-After cooldowns stop instead of repeatedly contacting the service.
- Consecutive local tool results share a stable Activity disclosure. Related operations are grouped within it. Public response text, plans, route previews, and interactive working surfaces retain their own positions. Consecutive hosted web activities also group together. Activity size does not grow with every completed read.
- Expanded tools show labeled requests, outcomes, source excerpts, lists, dates and counts. Code remains an explicit code disclosure. Raw protocol data is available through Copy diagnostic record, rather than being the normal reading experience.

## Continued work and attention

The connected-model path requests Apple's `BGContinuedProcessingTask` for a task the user starts in the foreground. It uses CPU/network resources, the system's visible activity and cancellation control, and genuine progress observations without an invented completion percentage. A denied request falls back to the short completion window and saved recovery. This is not a future scheduler or an unlimited background daemon.

Downloaded and Apple on-device models still pause on background entry; GPU access has separate entitlement requirements. A system-ended continued task requires a deliberate continuation rather than defeating the system cancellation control with an immediate restart.

Optional local notifications explain that a reply is ready, progress needs attention, or an action awaits review. Tapping routes to its chat. A native review that has not yet appeared is journaled as awaiting review; it can be rebuilt without repeating an authorized action. Once a review is presented, an interruption without a final receipt remains an unknown outcome. No approval is inferred from tapping a notification. Notifications require the user's iOS notification permission and do not require an assumed remote-push entitlement or server.

Settings provides background-continuation and attention-notification controls. `get_app_context` reports the requested preferences without claiming iOS granted indefinite execution. Physical testing must establish actual behavior under this sideloaded installation, screen lock, low power, network changes and OS expiration.

## Diagnostic view and rehearsal

The chat menu's Task activity view shows the saved phase, rounds, recovery count, receipt coverage and action outcomes. Its shareable diagnostic report excludes prompt text, tool arguments/results, source excerpts, file paths, location, account identifiers, credentials and arbitrary error bodies. Per-tool full-record copying remains a separate deliberate action.

Synthetic tests cover context pressure, recursive history, stale task cards, visible retry, partial output replacement, cancellation during retry, invalid retry classes, read-before-approval recovery versus uncertain effects, stable activity height and diagnostic redaction. Tests make no paid model calls. The new native scenario combines grouped history, readable details, visible recovery and absence of the old Continue card.

## Selection from the suggested ideas

| Decision | Ideas | How to make them useful |
| --- | --- | --- |
| Implement in 0.7 | Long-task recovery, grouped evidence, action outcomes, background attention, diagnostics and rehearsal | Address observed failures together and preserve evidence about exactly what happened. |
| Expanded 0.7 | Calendar availability and Reminders | Start with reading an authorized time range, conflict checks and reviewed creates/changes; retain stable event IDs and before/after receipts. Do not promise multi-person availability without their calendar access. |
| Expanded 0.7, except Share extension | Capture-to-action, evidence requests, Siri inbox | Route a deliberate input to an existing chat/project, support save-only capture, and let a task ask for a specific missing photo/text/measurement. A targeted evidence request is more useful than a generic camera button. |
| Build on existing objects | Shared attention, mini-tools, source-linked project context | Reuse existing file/capture/route/surface identifiers and versions. Add selection references and project associations rather than another parallel notes database. Existing charts, checklists and parameter surfaces already provide part of this capability. |
| Worth a distinct milestone | Reusable procedures and tested saved transformations | Store inputs, steps, examples, completion criteria and allowed operations. Generated functions keep the existing sandbox limits; a saved function does not receive extra device access. |
| Worth a distinct milestone | Task completion definitions, revisions, assumptions and recovery | Add explicit goal outcomes and dependency/version checks. Withdrawing an outdated proposal is different from undoing an action already completed. Keep unknown outcomes explicit. |
| Conditional integration | Email, contacts, authenticated services and calendar sharing | Add one supported provider or native framework at a time with real authorization and observable results. Do not claim Messages history or delivery access from the message composer API. |
| Conditional architecture | Scheduled monitoring, future execution, remote compute and rich Office tools | First establish a dependable executor, authentication, cost controls, and a scheduling/delivery contract. Local notifications can remind but cannot guarantee model execution while the app is suspended. Keep the ChatGPT-account connection primary. |
| Later, evidence-driven | Physical object records, NFC, RoomPlan, hands-on projects and offline packs | Good once capture/project references are established. Verify offline contents; distinguish scan estimates from measured dimensions. Avoid creating a separate complex subsystem before there is a concrete recurring use. |
| Keep deliberate | Voice/camera sessions, attention modes, local/cloud processing choices | Extend existing voice/capture and permission controls. Do not infer a psychological mode or silently start recording. |
| Defer | Home/music accessory routines, generalized multi-device surfaces, personal experiments | Potentially useful, but lower priority than finishing the current phone workflows. Watch already has a request bridge; strengthen that before adding another surface. |
| Do not promise | Universal control of every app, delivery/navigation proof without an API, unrestricted background execution, automatic powers for generated code | Being a private app does not remove the iOS sandbox or create evidence about actions it cannot observe. |

## Research applied

- [Apple: continued processing](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados): user-started foreground work, CPU/network background processing, visible system activity, cancellation and resource constraints.
- [Apple: continued request identifiers](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest/init(identifier:title:subtitle:)): bundle-based wildcard registration and unique request identifiers.
- [Apple: local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app) and [notification responses](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions): local attention delivery and routing from a notification tap.
- [OpenAI: compaction](https://developers.openai.com/api/docs/guides/compaction): long workflows need bounded working context. The public API documentation does not establish account-endpoint support for server compaction. This release uses app-owned request reduction and preserves original evidence instead of blindly enabling an unverified endpoint feature.

## Release gate

Windows core tests and syntax parsing are separate from an Xcode typecheck, native interaction test and device archive. Mac runs remain capped at 20 minutes. Jacob authorized USD 12.68 remaining from the recorded USD 19.902 estimate. Every new hosted job must fit that incremental allowance. The source checkpoint passes 161 core tests; 22 native platform tests and 15 interface scenarios await execution. No 0.7 IPA is claimed until native validation and archive inspection succeed.

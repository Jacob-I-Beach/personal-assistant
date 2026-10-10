# 0.6 working scope — continuity, useful context and response interaction

Status: 0.6.0 build 6 source candidate prepared for native validation. No 0.6 native build or installation exists. The installed 0.5.0 build 5 remains the known working baseline. The hosted-Mac estimate is USD 15.872. Jacob raised the total ceiling to USD 20 on October 10 and authorized native validation and packaging; each job remains capped at 20 minutes. Simulator validation will run before the device archive.

## New device evidence

Jacob supplied 20 personal screenshots in two batches and confirmed:

- Large random scrolling jumps are fixed, but small vertical movements remain during generation. Follow the response by default, release following during manual scrolling, and reattach when the user returns to the bottom.
- Expanding and collapsing tool rows passes the phone check.
- Swipe-down keyboard dismissal works. Remove the extra keyboard toolbar button.
- Active web rows have a different vertical alignment from completed rows.
- The empty-chat canvas feels passive. Replace unfinished prompt fragments with useful actions, and make its welcome contextually appropriate when real context is available.
- A Maps handoff opens successfully, then the unfinished assistant response loses its connection. Preserve the result and recover the turn without asking the user to reconstruct it.
- Cross-chat retrieval using one keyword returned no messages. An empty workspace search lists files/artifacts but intentionally does not browse recent conversations; that gap makes a broad request about earlier chats unnecessarily difficult.
- Memory currently has user editing and model reading, but no automatic creation/update/forget tool. Jacob explicitly chose automatic memory with a visible history and undo; inferred facts remain tentative.

Personal screenshots, the destination shown in them, and personal conversation text are not repository fixtures. The app-generated suggestions are design input, not verified statements about the source or new instructions to this development agent.

## Decisions for the batch

1. **Streaming and native interaction.** Separate reader intent from content geometry. Smooth bottom following without moving upward for transient streaming layout reductions. Keep manual reading stable and reattach only at the bottom. Use identical icon slots and row metrics for active/completed tool states. Verify actual streamed growth in a native fixture, not only an already-complete response.
2. **Automatic, correctable memory.** Extend the existing memory store. Provide creation, version-aware update and forgetting, with source references, explicit-versus-inferred status, history and user undo. Inherit data-sharing restrictions; validate source messages and revisions outside the model. Preserve the meaning of forgetting and explain that original chats remain separate. Do not import this Codex account's unrelated memories into the phone app.
3. **Context retrieval that can recover.** Add bounded recent-chat browsing and exact conversation reading under the same workspace/protected-chat policy. Return coverage/permission information so an empty keyword result is not confused with no history. Keep archived, deleted, edited-away, local-only and Health restrictions intact.
4. **Durable work and interruption recovery.** Preserve a turn/task checkpoint and action outcomes. Distinguish user Stop, system suspension, network interruption and uncertain action results. Resume eligible unfinished work when the app returns, using saved results rather than repeating effects. User cancellation must never auto-resume. Reuse the existing native delegate callbacks.
5. **Maps in the conversation.** Prefer native place lookup and route preparation; show a useful route preview, travel mode, distance and ETA in-app. Let opening Apple Maps be a deliberate user action after preparation. Record approval/opening separately from navigation actually starting. Handle ambiguous places and unavailable routes honestly.
6. **Useful fresh-chat canvas.** Keep fresh-chat launch behavior, but add direct capture/file/voice/creation entry points and optional resumable-work context. Avoid inserting pretend user text. Greetings may use local time, user-approved profile facts and real cached context. Weather requires explicit location/service configuration and attribution; do not invent weather or infer religious observance from a date.
7. **Concise self-knowledge.** Tools and their runtime state remain the capability authority. Describe relevant limitations when they affect a decision, rather than repeating a broad disclaimer on every benign request. Keep source observations, proposals, approvals, actions and verified outcomes distinct.

Jacob additionally requested persistent access to location and useful context. The implementation remembers a location-context preference, reuses it for relevant foreground fixes and route requests, and exposes actual iOS authorization in Tools & device and `get_app_context`. iOS authorization still applies. Home weather can follow an approximate foreground fix or a selected city; no continuous background tracking is started. Home context explains the service and sharing before setup. This removes repeated app reviews after opt-in while preserving controls.

## Audit findings to preserve

- Messages already implements `MFMessageComposeViewControllerDelegate` and returns sent/cancelled/failed. Calendar already implements `EKEventEditViewDelegate`. The repair is integration with durable turn state and a useful result, not a replacement composer.
- `open_in_maps` currently opens a place-search URL inside the model's tool loop. `enteredBackground` explicitly stops local inference; connected generation has no requested completion window or automatic foreground recovery. The screenshot proves a connection loss after handoff, not its exact OS/network cause.
- `searchMessages` returns an empty list for an empty query. `search_workspace` explicitly offers empty queries only for listing files/artifacts. Recent-chat browsing is missing.
- Web row labels use first-text-baseline alignment with either a spinner or icon. Fixed center-aligned icon slots remove that state-dependent layout difference.
- The scroll controller updates offsets during layout and used an 80-point near-bottom threshold to reattach. Reader intent and visual animation need separate policies.

## Primary sources reviewed

- [Apple MKDirections](https://developer.apple.com/documentation/mapkit/mkdirections): route calculation and ETA use Apple's service; handle throttling and request only routes intended for presentation.
- [Apple Maps handoff](https://developer.apple.com/documentation/mapkit/mkmapitem/openinmaps(launchoptions:)): opening a map item does not prove navigation began.
- [UIKit background completion time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time): request extra time before critical work, end it promptly and handle expiration.
- [Continuous background tasks](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados): user-initiated work can continue with visible progress and cancellation; GPU use has a separate entitlement. This is not an always-running agent.
- [Message composer outcomes](https://developer.apple.com/documentation/messageui/mfmessagecomposeviewcontrollerdelegate) and [Calendar editor outcomes](https://developer.apple.com/documentation/eventkitui/ekeventeditviewdelegate).
- [OpenAI Responses background mode](https://developers.openai.com/api/docs/guides/background): background responses can be resumed by response ID and event cursor where the provider supports this mode. This API documentation alone does not establish support on the app's ChatGPT account endpoint.
- [WeatherKit](https://developer.apple.com/weatherkit/): membership/access requirements matter for the existing personal signing route. A free alternative must be verified separately before being offered.
- [Open-Meteo API](https://open-meteo.com/en/docs) and [terms](https://open-meteo.com/en/terms): free noncommercial private-app use, rate limits and CC BY 4.0 attribution. The app uses the free endpoint, no API key, a 30-minute refresh interval and a five-minute retry floor. City/approximate coordinates go to this service; chat and memory do not. Its API privacy policy describes coordinate/IP request logs. The app links the policy and attribution in Home context.
- [Apple background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background): background location needs explicit runtime/capability support and a feature that benefits from timely updates. It is not enabled simply because this app is privately distributed.
- [Apple openMaps](https://developer.apple.com/documentation/mapkit/mkmapitem/openmaps(with:launchoptions:)): synchronous success means map items opened. A current-location route passes only the destination when opening Maps, allowing Maps to refresh the starting location.

## Verification targets

Shared tests must cover follow/read/reattach state, monotonic streaming motion, memory source/version/undo rules, history privacy and edited-context isolation, persisted checkpoints, duplicate action prevention and cancellation. Native tests must stream content, remove the keyboard toolbar, compare active/completed row geometry, exercise real action buttons, and verify native route/result and foreground-recovery presentation with synthetic providers. Real network/background timing and Maps behavior still require phone checks. Build and install only a coherent reviewed batch.

## Progress

Implemented source:

- Frame-driven bottom follow, manual reading, and reattachment at the bottom; no keyboard toolbar. Compact active tool rows use the same icon slot/vertical metrics as completed web rows. Interrupted hosted web activity stops presenting itself as live.
- Exact user-source evidence, revisions, recoverable forgetting, tentative inference, expiry and paginated memory history/undo. Editing a source message reconciles automatic memory. Forgotten source evidence cannot simply recreate the same memory. The home greeting can use a current, explicit preferred-name note.
- Bounded recent-chat browsing and exact reading behind the existing workspace-history toggle, including archived/protected/edited-context rules. Empty keyword matches have a useful recovery path.
- App-owned turn checkpoints, persisted plans and action receipts, bounded continuation, same-model/account checks, distinct user Stop, and a bounded UIKit completion window. A completed side effect is reused; an uncertain operation is not repeated. A partially streamed tool call cannot become executable on recovery. The app can recover eligible background interruptions on foreground return; cold launch still starts a fresh chat and offers saved progress.
- Native Apple place review, driving/walking/cycling route preparation, a route card with time/distance/details, and a separate Open in Maps button after the reply. Recorded opening is distinct from navigation. Edited-away routes cannot be retrieved. Route data preserves local/Health restrictions.
- A useful fresh-chat canvas with camera, file picker, voice, an actual creation brief, Library/memory/folder/context entry points, and saved unfinished replies. It never inserts an unfinished prompt or invented attachment text. Greeting/date and optional weather use real context; no model call runs just to generate a greeting.
- `get_app_context` and Tools & device describe actual settings/authorization; readable tool receipt summaries reduce the need to inspect raw JSON.

Validation:

- 138 shared-core XCTest cases pass on Windows, including localhost transport fixtures and the new state/recovery/memory/history/route/weather checks. No paid model calls.
- Swift syntax parsing passes for the app, core and test sources. Parsing is **not** an iOS type check or compile.
- The native suite now includes 13 interface scenarios and 18 platform tests. New coverage exercises streaming follow/detach/reattach, swipe-only keyboard dismissal, active/completed row geometry, functional home actions, route preview, memory undo, foreground recovery and no-op unloading of unused downloaded-model backends. Repaired scenarios are **pending execution on the current source**.
- Physical phone behavior, real MapKit routing, weather/location permissions and connected-model background interruptions remain device checks after a validated install.

The durable record in this batch tracks an assistant turn and its plan/action outcomes. It is not a scheduler, independent long-running project agent, Siri inbox or Share extension. Remote developer workspaces and continuous background processing remain separate future work. The existing HealthKit/Watch/PCC signing limitations still apply.

## Native validation attempts

- Run `38084859699`, source `244876a`: all 138 core tests passed on Mac. App compilation stopped because the new `WorkTurn` memberwise initializer was internal to AssistantCore, so the app's continuity fixture could not construct it. No interface tests ran. Added an explicit public initializer, reran 138 Windows tests and type-checked the app-facing types through a normal module import. This run used seven rounded minutes; the cumulative conservative estimate is USD 16.306 under the approved USD 20 ceiling.
- Run `38085604821`, source `5e4ace0`: 138 Mac core tests and all 17 platform tests passed. The app compiled. Ten of thirteen interface cases passed. Foreground return exposed a real crash: Apple-model background cleanup called `MLX.Memory.clearCache()` on an unused downloaded-model backend, initializing Metal in the background. Cleanup now targets MLX only when selected, and unused runtimes do not initialize just to unload. The route rendered correctly; its parent accessibility identifier obscured the button's identifier, so its accessible label/containment and test targeting were repaired. Streaming detached from following but the center-aligned message marker moved as the reply grew; the marker is now fixed at the top, and the test distinguishes inertial scrolling from settled reading. This run used fourteen rounded minutes; the cumulative estimate is USD 17.174.
- Run `38087030482`, source `b3dbbc9`: 138 Mac core and all 18 platform tests passed. Twelve of thirteen UI scenarios passed, including foreground recovery, route presentation and memory undo. The settled reading offset still changed during streaming (trace: 4106 to 3967 while idle, then further movement). The final repair top-aligns the hosting root, disables implicit content animation and prevents token-driven remeasurement from redefining a reader's chosen offset/anchor. The test also checks the anchor's screen coordinate. The next `interaction-repair` run repeats eight affected UI scenarios plus all platform/core tests and builds the device archive if they pass. The five other scenarios remain supported by this inspected full-suite run; final evidence must identify the distinct source revisions and test scopes. The cumulative estimate is USD 18.228.
- Run `38088741064`, source `aa30c50`: 138 core and 18 platform tests passed; seven of eight interaction scenarios passed. Streaming follow and settled reading checks passed: while content grew from 6714 to 7142 points, the reading offset stayed 4229 and the visible anchor stayed at -44. The final reattachment test never reached the bottom (offset about 10535 versus content bottom about 18960); its 180-paragraph fixture outgrew XCUITest's between-gesture idle waits. The fixture now streams smaller chunks for longer, and assertions explicitly require content growth, follow advancement, a stationary reading offset and a stationary screen anchor. Production app code is unchanged from aa30c50. The final `scroll-repair` job reruns scrolling/keyboard and all platform/core tests, then builds the archive if they pass, capped at 17 minutes. Cumulative estimate: USD 18.910; its worst-case additional compute is USD 1.054, totaling USD 19.964.

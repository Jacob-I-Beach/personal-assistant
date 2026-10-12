# 1.0.3 — coherent activity and live results

Candidate version 1.0.3, build 14. Jacob confirmed Tailscale pairing works and a response continues after leaving the iPhone app. His next three screenshots identify an early system completion checkmark, unclear custom Island state, and missing research receipts until a response finishes.

## Added

- Public web-search and page-reading events in the PC's durable stream, including their ordering, current status, queries and citation positions. These appear in the chat while the answer is still generating and survive replay.
- A saved replay boundary. Returning to a chat retains its newer saved transcript until older event pages catch up; it does not briefly replace it with a partial history.
- A ready-to-open activity state with a green check. Opening the corresponding chat acknowledges it; starting new work replaces it. Working, waiting, reconnecting and ready remain distinct.

## Changed

- The same iOS processing window carries through the direct-to-PC handoff and progress subscription. A handoff no longer completes that window and produces a premature checkmark. Actual received progress advances the counter; empty polls do not invent completed work.
- Final activity updates and completion notifications are delivered before releasing the iPhone's execution window. A connection interruption does not become a successful completion signal.
- The custom compact Island uses a native circular progress indicator. Expanded and Lock Screen layouts share a restrained model header, current step, one useful recent step and elapsed time. Ready results stop the timer; lost updates are described as reconnecting rather than finished.
- Tool groups summarize observed work and useful subjects rather than saying only “Activity” or “Web research.” Repeated chat/document reads receive counts, research distinguishes searches from page reads, and partial failures remain visible.
- Disclosures have consistent touch areas, clearer nested backgrounds and smaller cumulative indentation while preserving the tapped reading position. Interactive working cards share an icon/title header, softer border and a clear next action.
- Completion notifications use a stable per-chat identity and clear old notifications when that chat is opened, including after a cold launch.

## Removed

- The automatic successful completion of the iOS processing segment at handoff.
- The waveform used as the working indicator in the custom compact Island.
- Automatic removal of a ready custom activity after 60 seconds.
- Generic top-level activity category headings where actual work can be summarized.

## Validation and device limits

191 Windows shared-core tests and 16 synthetic companion checks pass before native validation. New checks cover live research before completion, stable replay identity and ordering, preserved saved transcript boundaries, meaningful summaries, and refusal to expose opaque reasoning through public progress. Native lifecycle, visual components, live transcript return, interactive cards and disclosure anchoring use a focused validation scope.

The large system processing banner and the custom ActivityKit view are separate iOS presentations. iOS controls their prominence, gestures and collapse timing; the app cannot force them to behave as one custom expandable sheet. This update fixes their task lifecycle and the presentation owned by the app.

The ready result stays available until viewed or replaced, subject to iOS's Live Activity lifetime and dismissal rules. Motion also follows system presentation, Reduce Motion and Always-On behavior. The native progress indicator is not a fabricated percentage or a custom perpetual animation.

The preserved background execution window permits live synchronization while iOS grants execution time. Fully suspended/terminated app updates still need APNs provisioning, which the current signing route does not provide. The PC continues independently and the chat catches up on return. This update does not claim to deliver fresh Island state while the phone is powered off or its app cannot receive updates.

Install the iPhone build in place with the existing signing identity. The matching PC companion update preserves its certificate, device credential, account and task store; another pairing is not required.

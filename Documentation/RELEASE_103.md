# 1.0.3 — coherent activity and live results

Packaged version 1.0.3, build 14. The iPhone archive is from source `86135dec5b269d62b3a7f6ffc13898328ef0a5fb`, [run 38206367024](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38206367024). The computer companion is already updated and runtime-verified. Jacob confirmed the prior Tailscale pairing and continued off-app generation; this release addresses his three screenshots of an early system completion checkmark, unclear custom Island state, and research receipts appearing only after completion.

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
- A group containing only one category opens directly to its receipts; another category disclosure appears only when it helps organize mixed work. Research subjects lead the heading, with search/page/source counts underneath.
- Completion notifications use a stable per-chat identity and clear older alerts for the same task when its notification is opened, including after a cold launch.

## Removed

- The automatic successful completion of the iOS processing segment at handoff.
- The waveform used as the working indicator in the custom compact Island.
- Automatic removal of a ready custom activity after 60 seconds.
- Generic top-level activity category headings where actual work can be summarized.
- The redundant second disclosure for groups that contain only one category.

## Validation and device limits

191 Windows and Mac shared-core tests and 16 synthetic companion checks pass. New checks cover live research before completion, stable replay identity and ordering, preserved saved transcript boundaries, meaningful summaries, and refusal to expose opaque reasoning through public progress.

Three native lifecycle/attention checks and the four-state component preview passed in run 38204753846. Native screenshots were inspected. Two initial chat checks found inherited disclosure identifiers; those were corrected, and the live research/return/interactive-card flow passed on the final app source in run 38206367024. The remaining legacy check asserted tappability of noninteractive Markdown despite the captured answer being visible at the bottom. Its corrected bounds/visibility assertion passed in [run 38208549889](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38208549889), which rebuilt only the UI test bundle and verified that production source matched the existing app. No unchanged app or model bundle was rebuilt for that last check. The final coverage is three focused native platform checks and three focused UI flows, with exact provenance in `ReleaseValidation103.json`.

The real iPhone archive is verified for ARM64, bundle identity, Health setting, Activity extension, version/build, checksum and the preserved Tailscale transport policy. Phone installation and actual system Island/background behavior remain physical acceptance checks.

The large system processing banner and the custom ActivityKit view are separate iOS presentations. iOS controls their prominence, gestures and collapse timing; the app cannot force them to behave as one custom expandable sheet. This update fixes their task lifecycle and the presentation owned by the app.

The ready result stays available until viewed or replaced, subject to iOS's Live Activity lifetime and dismissal rules. Motion also follows system presentation, Reduce Motion and Always-On behavior. The native progress indicator is not a fabricated percentage or a custom perpetual animation.

The preserved background execution window permits live synchronization while iOS grants execution time. Fully suspended/terminated app updates still need APNs provisioning, which the current signing route does not provide. The PC continues independently and the chat catches up on return. This update does not claim to deliver fresh Island state while the phone is powered off or its app cannot receive updates.

Install the iPhone build in place with the existing signing identity. The matching PC companion update preserves its certificate, device credential, account and task store; another pairing is not required.

The PC package includes `Update-Companion.cmd`. It checks that the existing task list is idle, closes the companion through its reviewed local setup endpoint, requests administrator approval only to retarget the existing Tailscale firewall rule, starts the new companion as the normal Windows user and updates sign-in startup. Jacob subsequently approved the Windows prompt. Version 1.0.3 is now running on the PC; pinned Tailscale HTTPS, the startup path, firewall program and two retained pairings were verified. The iPhone update is ready for in-place installation after final validation is recorded.

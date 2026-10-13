# 1.1.1 build 16 — account, continuity and tool coherence

Candidate dated October 13, 2026. Native compilation and packaging are pending. The installed baseline is user-confirmed 1.1.0 build 15 Standard, with prior chats retained and connected GPT responses working. The user-operated Computer r4 update is active with its preserved account, pairing and tasks.

## Added

- A shared, locally cached account display sourced from the paired computer's existing authenticated capabilities response. The model picker and Settings show the account email when supplied. Cached display metadata is bound to the server, paired device and profile; it contains no OAuth credentials.
- Focused regression coverage for detaching and rejoining the same saved task, truthful live message state, account identity boundaries, original-model recovery, and paged durable replay after a simulated 90-minute absence and store reopen.

## Changed

- Home recognizes the enabled computer account instead of asking for a second phone sign-in. Temporary connection loss, sharing disabled, changed account and required sign-in have distinct presentation.
- Loading a saved computer transcript no longer converts a still-streaming response to “Stopped · partial response saved.” The live engine preserves streaming state, and persisted recovery checks the actual saved task ownership/status. Genuine stopped and failed states remain visible.
- Cancelling the phone's observer leaves the remote task eligible for synchronization. It does not cancel the PC job. Reconnection uses the original task/model/account even if the model picker has changed, preserves the selected model for the next request, and respects on-device-only mode and account changes.
- Synchronization of an accepted job does not reconstruct another model prompt or reload its already-transferred input files. Transient connection failures retry the same task, including the first status request after return. Access/trust failures remain actionable instead of being retried indefinitely.
- System instructions explain the app as one workspace, encourage useful tool combinations and completed workflows, distinguish discussion from authorized action, identify narrow service failures, and ground completion claims in actual receipts. Answer depth and tone remain flexible; there is no fixed response template or mandatory tool inventory call.
- Python now preloads the documented `assistant` helper. `assistant.publish`, file handles and saved state work without a preliminary import; explicit `import assistant` also works. Each execution still has its own globals and selected inputs.
- Docker's stale runtime socket directories were quarantined after checking that Docker was stopped. Images, account data, task data and WSL disks were preserved. The existing computation image tag now resolves to the repaired helper; its former image is retained for rollback. This does not require a companion service restart.
- The native archive workflow produces the preferred Health-disabled Standard IPA directly and retains its Live Activity extension.

## Removed

- False phone sign-in prompts for an already connected computer account.
- The implicit requirement to import a helper that the tool description presented as available.
- The use of a phone subscription interruption as evidence that the server-owned answer stopped.

## Validation and remaining acceptance

Local shared-core and targeted companion tests use synthetic data, not a live model account. The real Docker check executes a CSV calculation without importing the helper, reuses saved state in another execution, creates a workbook and PDF, and reopens both for structural/rendered inspection. It also verifies isolated file/network boundaries.

Native build, focused account/recovery platform tests, account UI flow and archive inspection are required before handoff. Physical installation, long-duration locked-phone reconnection and live model answer quality remain phone acceptance checks; synthetic time advancement is not a claim of an actual 90-minute phone test.

PC work continues while the phone is away as long as the PC can run the job and reach its provider. Phone-only actions can wait for the phone, and model/service/time allowances still apply. No unlimited-execution promise is made.

Apple enrollment and native APNs provisioning remain deferred. Existing local notifications and app-updated Live Activities work independently of remote push. A Home Screen web app can receive standards-based Web Push without paid Apple Developer membership, but that is a separate proposed notification path, not implemented native ActivityKit delivery. Sources: [Apple ActivityKit](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications), [WebKit Web Push](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/).

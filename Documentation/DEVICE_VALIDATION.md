# Private 0.5 device validation

The 0.5.0 build 5 package passed [full native validation 38062830456](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38062830456) and archive inspection. Jacob has not yet confirmed installing this version. Automated checks use synthetic data; the following phone checks establish real behavior.

## Installation profile

The current official iLoader 2.3.6 uses isideload 0.4.3. Its bundle discovery registers the main app and PlugIns, but does not register or provision Watch bundles. Its provisioning path enables its app group, but does not request HealthKit. It signs using the downloaded profile's entitlements, rather than retaining arbitrary requested capabilities from the input executable.

Therefore the release provides two archives from the same compiled iPhone executable:

- `PersonalAssistant-iPhone-only.ipa`: the input for the currently installed official iLoader. The unsupported embedded Watch directory is omitted. Health reads are explicitly unavailable in the app, before either authorization or querying. The app identifier stays `dev.jacob.personalassistant` before iLoader applies the same signing-team suffix as the previous install.
- `PersonalAssistant-unsigned.ipa`: the complete iPhone and Watch build, retained for a signing route that provisions both targets. This is not the file to install with iLoader 2.3.6.

Both need Apple personal signing. The ad-hoc build seal is not device authorization. `prepare_iloader_package.py` verifies that the iPhone executable is byte-identical between these profiles. The original 0.1 package is retained in the parent output folder.

Health can be enabled in a future deployment only after the final signed application's profile and code entitlements contain `com.apple.developer.healthkit`. Set `AssistantHealthEnabled` to the Boolean `true` in that verified deployment's Info.plist; merely changing this flag does not grant permission. Watch requires matching host/companion identifiers, both provisioning profiles, registration of the paired Watch, and its installation path. Consumer Apple Intelligence/PCC access does not establish the separate managed entitlement for this app.

Source evidence: [official iLoader 2.3.6](https://github.com/nab138/iloader/tree/v2.3.6), pinned isideload 0.4.3 crate SHA-256 `46de455a50785bb772f4a1e586420a12861a07f4607fe5b0a5b2507da6a5c4bd`. The reviewed implementation is `sideload/bundle.rs`, `application.rs`, `sideloader.rs`, and `sign.rs`. An independent Watch-support fork exists, but has not been audited, installed, or given Jacob's credentials.

## User-operated installation

1. Leave the existing Personal Assistant installed. Connect and unlock the iPhone, then select it in iLoader with the same Apple account used for the working installation.
2. Choose **Import IPA** and select the verified `0.5.0/PersonalAssistant-iPhone-only.ipa` in the `PersonalAssistant-iPhone` output folder.
3. Complete any Apple authentication prompt yourself. If iLoader proposes revoking a certificate, deleting another app, or changing accounts, stop and report the exact message so the existing installation can be preserved.
4. After iLoader reports success, open Personal Assistant on the phone. Check About for **Version 0.5.0 · Build 5** and find prior conversations in the sidebar. Do not uninstall the old app to solve an update failure.

The agent performs code/CLI/file validation; Jacob requested instructions for all GUI interactions rather than computer-use automation.

### If the signing helper returns HTTP 502

The first 0.2 attempt failed in the selected anisette service's `/v3/get_headers` operation, before iLoader listed Apple developer devices or installed the app. In official iLoader 2.3.6, select **Settings → Anisette Server → SideStore (.app)**, then sign out and back into the same account **inside iLoader** before retrying Import IPA. The server choice is applied when the account session is created, not by changing the active session in place. The public service-info endpoint was reachable when checked; this is not proof that an individual signing request succeeds. This error does not call for changing the IPA or deleting the existing phone app.

Sources: [official preset list](https://github.com/nab138/iloader/blob/v2.3.6/src/pages/Settings.tsx), [official account/session implementation](https://github.com/nab138/iloader/blob/v2.3.6/src-tauri/src/account.rs).

## First functional pass

1. **Update:** About shows Version 0.5.0, Build 5; prior chats remain. A cold launch starts a fresh conversation.
2. **Position/keyboard:** open the earlier long research answer, scroll to the middle, expand/collapse a tool and type a draft. Swipe down to dismiss the keyboard, then try its dismiss button. The reading position should stay sensible without random jumps. Repeat while a long answer streams.
3. **Thinking/layout:** select GPT 6.1 Sol; use the circle beside the microphone to try Low through Max. Check normal contrast, compact tool rows, retained collapsible sources, tight user bubbles and external action rows.
4. **Edit/regenerate:** in a disposable chat ask 1+1, edit it to 1+2 and send. The replacement answer should use 1+2 and the removed tail should disappear. Cancel a second edit and confirm the draft is restored. External files are not undone by editing.
5. **Attachments:** send an ordinary photo without text. No inserted sentence or empty text bubble should appear. Tap the photo to zoom. Attach a small PDF with text and open it from its attachment row.
6. **Depth:** open a non-sensitive saved camera/depth capture. Select one or two visible points, inspect the result/warnings and use selected points in chat. The draft text must remain unchanged. Ask about those points; the assistant should use saved sensor metadata with its limitations. Do not use this uncalibrated workflow for safety or guaranteed fit.
7. **Working surfaces:** ask for a JavaScript calculation and a chart based on that exact result; then a small comparison/checklist or adjustable scenario. Change a selection/parameter, send a follow-up and confirm read_surface sees the new saved state. Checkmarks are not evidence of completed external actions.
8. **Memory:** Library → Saved memory. Mark a disposable note tentative, expired or superseded; inspect its source/confirmation and connected-model scope. Expired/superseded notes should stop being injected as current memory. Prior transcript references remain historical data.

Existing Files/export/folder workflows should still work. Real document-provider persistence, account-specific model support, local-model performance and hardware behavior remain separate checks.

## Not part of this installed profile

Health reads and Watch installation remain blocked by the current signing route. Direct PCC awaits the app entitlement. Full browser automation, Python, a cloud execution workspace, unattended continuous background work and arbitrary iOS device control are not implemented. Local model throughput/thermal suitability and actual Siri shortcut discovery remain unmeasured/unverified. Web search depends on the selected ChatGPT model and account policy.

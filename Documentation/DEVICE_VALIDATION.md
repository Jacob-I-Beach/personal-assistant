# Private 0.4 device validation

The 0.4.0 build 4 package passed [final native validation 38028597942](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38028597942) and archive inspection. Six additional interface scenarios passed on identical app source in run 38027478506. Jacob's current confirmed installation is 0.3.0 build 3. Automated checks use synthetic data; live accounts and hardware need the checks below.

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
2. Choose **Import IPA** and select the verified `0.4.0/PersonalAssistant-iPhone-only.ipa` in the `PersonalAssistant-iPhone` output folder.
3. Complete any Apple authentication prompt yourself. If iLoader proposes revoking a certificate, deleting another app, or changing accounts, stop and report the exact message so the existing installation can be preserved.
4. After iLoader reports success, open Personal Assistant on the phone. Check About for **Version 0.4.0 · Build 4** and find prior conversations in the sidebar. Do not uninstall the old app to solve an update failure.

The agent performs code/CLI/file validation; Jacob requested instructions for all GUI interactions rather than computer-use automation.

### If the signing helper returns HTTP 502

The first 0.2 attempt failed in the selected anisette service's `/v3/get_headers` operation, before iLoader listed Apple developer devices or installed the app. In official iLoader 2.3.6, select **Settings → Anisette Server → SideStore (.app)**, then sign out and back into the same account **inside iLoader** before retrying Import IPA. The server choice is applied when the account session is created, not by changing the active session in place. The public service-info endpoint was reachable when checked; this is not proof that an individual signing request succeeds. This error does not call for changing the IPA or deleting the existing phone app.

Sources: [official preset list](https://github.com/nab138/iloader/blob/v2.3.6/src/pages/Settings.tsx), [official account/session implementation](https://github.com/nab138/iloader/blob/v2.3.6/src-tauri/src/account.rs).

## First functional pass

Start with these short checks; use a disposable folder and non-sensitive image.

1. **Install/migration:** About shows Version 0.4.0, Build 4. A cold launch opens a fresh conversation; existing chats remain in the sidebar.
2. **Thinking and titles:** choose GPT 6.1 Sol. Tap Thinking below the composer, choose High, send a short task, then check the title after its successful answer. Switch models and back to check the remembered selection. Manual renaming must remain authoritative.
3. **Photos/vision:** plus → Photo library opens the native picker. Choose one picture and send it; a response or actionable error must remain. Repeat the earlier camera/depth request separately. The simulator verified picker opening/cancellation, not a real camera observation.
4. **Response layout/sources:** repeat a sourced calculation. Public updates remain separate, web activity is visible, calculation results are readable and equations render. The completed turn has one action row; more than three unique source URLs appear in a collapsible panel.
5. **Generated files:** ask the assistant to use JavaScript to add [18.5, 27.25, 14.75], then save the computed values/total as CSV and create a small PDF report. Confirm total 60.5, genuine CSV rows and a readable PDF. Check Files → On My iPhone → Personal Assistant → Outputs. A signed app/provider may display a localized app-folder name.
6. **Export:** open an artifact and Save to Files. Cancel first and confirm the app reports cancellation. Repeat and save a deliberate copy; local completion must not claim cloud sync is finished.
7. **Connected folder:** plus → Connected folders; choose a disposable folder with notes.md. Enable it for this chat, and allow connected-model access only if desired. Ask to list/read it, then authorize editing and request a small change. Inspect the native diff and original copy. Close/reopen the app and check access again. If a provider is unavailable or access is revoked, the app should offer reconnection, not invent a successful read/save.

Existing integration checks remain useful when testing those features: cancel location, Calendar or Messages review before deliberately approving an action; verify no success is claimed for cancellation. For local inference, use an already downloaded package or an explicitly chosen download and record latency/heat rather than trusting catalog estimates. Text-only models use saved OCR; direct image interpretation requires a vision-capable model.

Watch, Health entitlement, PCC entitlement, continuous background work, Python and full browser control are not acceptance claims for this iPhone-only package.

## Not part of this installed profile

Health reads and Watch installation remain blocked by the current signing route. Direct PCC awaits the app entitlement. Full browser automation, Python, a cloud execution workspace, unattended continuous background work and arbitrary iOS device control are not implemented. Local model throughput/thermal suitability and actual Siri shortcut discovery remain unmeasured/unverified. Web search depends on the selected ChatGPT model and account policy.

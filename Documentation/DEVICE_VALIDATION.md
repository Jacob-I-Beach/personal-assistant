# Private 0.3 device validation

The 0.3.0 build 3 package passed native validation 38016040142 and archive inspection. Jacob reports that the in-place update opens and previous chats are present. Automated tests use synthetic data; live accounts and hardware need the checks below.

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
2. Choose **Import IPA** and select the verified `0.3.0/PersonalAssistant-iPhone-only.ipa` in the `PersonalAssistant-iPhone` output folder.
3. Complete any Apple authentication prompt yourself. If iLoader proposes revoking a certificate, deleting another app, or changing accounts, stop and report the exact message so the existing installation can be preserved.
4. After iLoader reports success, open Personal Assistant on the phone. Check About for **Version 0.3.0 · Build 3** and find prior conversations in the sidebar. Do not uninstall the old app to solve an update failure.

The agent performs code/CLI/file validation; Jacob requested instructions for all GUI interactions rather than computer-use automation.

### If the signing helper returns HTTP 502

The first 0.2 attempt failed in the selected anisette service's `/v3/get_headers` operation, before iLoader listed Apple developer devices or installed the app. In official iLoader 2.3.6, select **Settings → Anisette Server → SideStore (.app)**, then sign out and back into the same account **inside iLoader** before retrying Import IPA. The server choice is applied when the account session is created, not by changing the active session in place. The public service-info endpoint was reachable when checked; this is not proof that an individual signing request succeeds. This error does not call for changing the IPA or deleting the existing phone app.

Sources: [official preset list](https://github.com/nab138/iloader/blob/v2.3.6/src/pages/Settings.tsx), [official account/session implementation](https://github.com/nab138/iloader/blob/v2.3.6/src-tauri/src/account.rs).

## First functional pass

Check About shows Version 0.3.0, Build 3. Reopen the app to a fresh conversation, then find the old 0.2 chats in the sidebar. Test folder/move/archive/restore with a disposable chat before deleting anything you need.

Priority regression: choose GPT 6.1 Sol. Ask it to estimate Jupiter's circumference from explicitly limited observations, identify assumptions, research any missing factual inputs, and calculate with JavaScript. An answer, tool receipt or visible error must remain; silently disappearing generation fails the check. Repeat with a camera/depth image. Source links must open and correspond to claims.

Calculation: Use JavaScript to add [18.5, 27.25, 14.75] and save the values and computed total as totals.csv. The total must be 60.5 and the file must contain CSV rows. Repeat with the Apple on-device model if available.

Files: attach a non-sensitive PDF or DOCX using the plus menu. Ask for a cited summary and a small new PDF. Confirm originals and generated PDF appear in Library and can preview/share. Verify a new unrelated chat cannot find a private file until workspace/file access is enabled.

Actions: ask for device memory/thermal state. Request location and first Cancel; no coordinates should appear. For Calendar and Messages, cancel the native composer first and verify the assistant does not claim success. Save/send only a deliberate test you actually want. Calling and Maps require their separate review.

Local inference: select one already downloaded package or explicitly choose a download. Record first-load time, approximate response speed, device heat and any visible failure; do not infer performance from the catalog estimate. Vision behavior needs a vision model; text models can use saved OCR.

Watch, Health entitlement, PCC entitlement, continuous background work, Python and full browser control are not acceptance claims for this iPhone-only package.

## Not part of this installed profile

Health reads and Watch installation remain blocked by the current signing route. Direct PCC awaits the app entitlement. Full browser automation, Python, a cloud execution workspace, unattended continuous background work and arbitrary iOS device control are not implemented. Local model throughput/thermal suitability and actual Siri shortcut discovery remain unmeasured/unverified. Web search depends on the selected ChatGPT model and account policy.

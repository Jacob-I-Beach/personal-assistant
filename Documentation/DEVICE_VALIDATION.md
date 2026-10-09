# Private 0.2 device validation

This is a substantial development candidate. Jacob reported that the earlier 0.1 app opens. Simulator tests and core tests establish implementation behavior with synthetic fixtures; they do not establish live account access, on-phone model performance, or real sensor behavior.

## Installation profile

The current official iLoader 2.3.6 uses isideload 0.4.3. Its bundle discovery registers the main app and PlugIns, but does not register or provision Watch bundles. Its provisioning path enables its app group, but does not request HealthKit. It signs using the downloaded profile's entitlements, rather than retaining arbitrary requested capabilities from the input executable.

Therefore the release provides two archives from the same compiled iPhone executable:

- `PersonalAssistant-iPhone-only.ipa`: the input for the currently installed official iLoader. The unsupported embedded Watch directory is omitted. Health reads are explicitly unavailable in the app, before either authorization or querying. The app identifier stays `dev.jacob.personalassistant` before iLoader applies the same signing-team suffix as the previous install.
- `PersonalAssistant-unsigned.ipa`: the complete iPhone and Watch build, retained for a signing route that provisions both targets. This is not the file to install with iLoader 2.3.6.

Both need Apple personal signing. The ad-hoc build seal is not device authorization. `prepare_iloader_package.py` verifies that the iPhone executable is byte-identical between these profiles. The original 0.1 package is retained in the parent output folder.

Health can be enabled in a future deployment only after the final signed application's profile and code entitlements contain `com.apple.developer.healthkit`. Set `AssistantHealthEnabled` to the Boolean `true` in that verified deployment's Info.plist; merely changing this flag does not grant permission. Watch requires matching host/companion identifiers, both provisioning profiles, registration of the paired Watch, and its installation path. Consumer Apple Intelligence/PCC access does not establish the separate managed entitlement for this app.

Source evidence: [official iLoader 2.3.6](https://github.com/nab138/iloader/tree/v2.3.6), pinned isideload 0.4.3 crate SHA-256 `46de455a50785bb772f4a1e586420a12861a07f4607fe5b0a5b2507da6a5c4bd`. The reviewed implementation is `sideload/bundle.rs`, `application.rs`, `sideloader.rs`, and `sign.rs`. An independent Watch-support fork exists, but has not been audited, installed, or given Jacob's credentials.

## User-operated installation

1. Leave the existing Personal Assistant installed. Connect and unlock the iPhone, then select it in iLoader with the same Apple account used for 0.1.
2. Choose **Import IPA** and select the verified `0.2.0/PersonalAssistant-iPhone-only.ipa` in the `PersonalAssistant-iPhone` output folder.
3. Complete any Apple authentication prompt yourself. If iLoader proposes revoking a certificate, deleting another app, or changing accounts, stop and report the exact message so the existing installation can be preserved.
4. After iLoader reports success, open Personal Assistant on the phone. Existing saved conversations should remain. Do not uninstall the old app to solve an update failure.

The agent performs code/CLI/file validation; Jacob requested instructions for all GUI interactions rather than computer-use automation.

## First functional pass

Keep the first test small so failures have a clear cause.

1. **Launch and persistence:** confirm the new interface opens and old conversations are present. Check Settings and Models, then reopen the app.
2. **A real model:** choose an available Apple on-device model for a quick test, or download/import Qwen 3.5 4B. A Locally AI download can be reused only if that app exposes a complete compatible MLX folder matching the catalog revision; GGUF files and private app storage are not interchangeable. The catalog's Download action verifies the package; Use loads it separately.
3. **Tools and durable work:** ask, "Use JavaScript to calculate the total of [18.5, 27.25, 14.75], and save a CSV with the three values and the total." Check that the execution receipt reports 60.5 and that the artifact opens. This also tests whether the selected model can call tools correctly.
4. **ChatGPT:** tap Continue with ChatGPT. Complete authorization on OpenAI's page. Return to the app, choose an account model, and run a short conversation. Inspect the network-sharing prompt before allowing it. This does not import the ChatGPT app's existing chats, memories, Health permissions, or hosted tools.
5. **Memory:** save an on-device-only preference. Confirm it can be used locally and is withheld after switching to a connected model. Notes intended for connected models require their separate sharing setting.
6. **Voice/capture:** test editable dictation, stop/read-aloud, and one deliberate camera capture. These still need actual hardware verification.

The local model test should record the exact model/revision, whether loading succeeds, a short response's latency, whether tool use succeeds, and whether the app stops reliably. Larger model options remain available; no claim about their practical RAM or thermal performance is made before measurement.

## Not part of this installed profile

Health reads and Watch installation are blocked by the current signing route. Direct PCC awaits the app's entitlement. Document/PDF ingestion, full web research, larger Python/PC/cloud execution, conversation branching, richer interactive artifact previews, and broader organizer/sensor workflows remain development work. This candidate does not represent completion of the full product design.

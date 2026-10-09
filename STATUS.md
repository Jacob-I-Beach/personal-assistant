# Implementation status

This file records implemented features, validation evidence, and user-reported device checks.

## Current 0.2 candidate

The final source `c403e184dc2bfbeb5d4c776e24d4334bec112895` passed [native validation 38003037939](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38003037939): 50 macOS core tests, four iOS platform tests, three native UI tests, and the iPhone/Watch Release build. The same shared-core revision passed 50 Windows tests. Eight native screenshots are retained in `Documentation/Screenshots/0.2.0`; the changed welcome, dark/large-text, code-block, and Settings screens were visually inspected after the final run. These checks are not a full accessibility audit.

The verified installation input is `../PersonalAssistant-iPhone/0.2.0/PersonalAssistant-iPhone-only.ipa`, version 0.2.0 build 2, 13,431,742 bytes, SHA-256 `579b90fd6f679bd864a36bd61f5040ad5302e89e167000d5ffb8b211e26d5333`. It targets physical ARM64 iOS 27 and includes the Metal kernels. The complete iPhone/Watch archive and verification receipts are retained beside it. Neither package contains model weights or an Apple provisioning profile; local personal signing is still required.

All nine Mac jobs used 80 rounded runner minutes, an estimated $4.96 at $0.062/minute if entirely billable. This remains within Jacob's previously authorized $5 compute budget. Actual account charges, included allowance, taxes, and separate artifact storage are not established by this estimate. Evidence is in `Documentation/BuildValidation.json`.

Implemented source includes SQLite migration and search, bounded working context, actual offline JavaScript execution, durable editable artifacts, explicit saved memory and local-only classification, ChatGPT account authorization/model selection, Apple model adapters, a verified downloadable/importable MLX catalog, native voice input/read-aloud, Health overview logic, Watch request delivery/recovery, and rebuilt native screens. Details and remaining product scope are in [README.md](README.md) and [Documentation/IMPLEMENTATION.md](Documentation/IMPLEMENTATION.md).

Jacob has now reported that the updated 0.2.0 app is installed and opens on his iPhone. This is the latest physical installation/launch checkpoint. Live ChatGPT grant, real on-device inference/tool use, prior-chat preservation, physical Health reads, Watch exchange, and hardware benchmarks are not established by launch alone. The simulator uses synthetic conversation fixtures and does not establish model output quality.

Jacob confirmed the USB phone is visible in iLoader. His first 0.2 import stopped before installation: `Failed to list developer devices` -> `Failed to get anisette headers` -> HTTP 502 from `https://ani.sidestore.io/v3/get_headers`. The agent reviewed the exact official iLoader server/login code and provided manual steps to select its built-in SideStore (.app) preset, sign out and back into the same account inside iLoader, then retry the same verified IPA. The selected server is bound when the session is constructed at login. Public `/v3/client_info` requests returned HTTP 200 for the .io, .app, and .zip presets; that check alone did not verify signing. Jacob then confirmed, "Installed, and Version 0.2.0 opens." No desktop GUI actions have been taken since his request to handle GUI interactions himself.

The next requested physical test uses an available Apple on-device model to run JavaScript on `[18.5, 27.25, 14.75]`, return 60.5, and save/open `totals.csv`. Its result is awaiting Jacob's report.

### Installation boundary

Official iLoader 2.3.6 does not prepare Watch provisioning or request this app's HealthKit capability. The final build produces a complete archive and a separate iPhone-only input for the existing installer, with identical iPhone executable bytes. Health is visibly unavailable and its native authorization/query entry points are gated off in this installation profile. This avoids presenting an unprovisioned feature as connected. Neither a paid Apple enrollment nor an unofficial signer has been introduced. Direct PCC also remains gated pending the app's managed entitlement.

Exact user-operated installation and functional test steps are in [Documentation/DEVICE_VALIDATION.md](Documentation/DEVICE_VALIDATION.md). Jacob requested GUI instructions instead of computer-use automation; code/CLI/test work continues directly.

## Historical 0.1 verification

- Official Swift 6.4 Windows toolchain installed and functional.
- All 24 tests passed on Windows using `scripts/Test-Core.ps1 -Integration` and on macOS under Xcode 27: 12 core tests, 5 engine tests, and 7 real-HTTP/loopback tests.
- Cancellation preserves the partial response before the engine becomes idle.
- The HTTP tests exercised both provider protocols, a complete capture-tool loop, interrupted streams, provider failure, HTTP 401, and refused redirects. They used synthetic responses; no external model inference was called.
- All 10 native Swift source files passed a syntax parse. This does not type-check Apple SDK or MLX calls.
- Info.plist parsed successfully; the XcodeGen project and GitHub workflow YAML parsed successfully.
- The MLX Swift LM 3.32.3 and Hugging Face 0.9.0 source interfaces were checked against pinned references.
- The actual iOS simulator application compiled successfully with Xcode 27, including the MLX and camera modules.
- An XCUITest launched the app on an iPhone 18 Pro Max simulator with iOS 27, opened Settings and Captures, returned to Assistant, and checked for the absence of a startup-error alert. The test passed; its three screenshots are saved in `Documentation/Screenshots/` and were visually inspected.
- Successful native validation: [GitHub run 37914119728](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/37914119728), app source revision `ec84539`. The UI test exercised startup/navigation, not model inference or physical sensors.
- The first Mac runs identified and resolved fixture-runtime setup, a missing Metal compiler component, and one incorrect file-protection API argument label.
- The resolved native dependency versions are retained in `Dependencies/Package.resolved`.
- No physical camera/depth test or local-model benchmark has run yet.
- No cloud-model API key or provider token has been configured by the agent. Jacob entered his Apple signing credentials directly in iLoader; the agent did not read or export them.
- No model weights have been downloaded to this PC.
- The capture replay command was exercised with a synthetic saved observation.
- GitHub CLI 2.102.0 was downloaded to the thread's tooling directory and checked against its official SHA-256 list. It was not installed globally. Jacob completed device authorization for his GitHub account.
- The source is pushed to the private `Jacob-I-Beach/personal-assistant` repository. Repository visibility was verified through GitHub's API.
- The manual Mac workflow uses GitHub's standard `xcode-27` Apple silicon preview image; the `macos-26` image's published inventory does not include Xcode 27.
- Jacob configured GitHub billing and authorized continuing within the discussed $5 budget. Included Actions allowance could not be verified with the current GitHub login scopes; no account billing settings were changed by the agent.
- The physical-iPhone Release build succeeded: [GitHub run 37915018467](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/37915018467), revision `7b26c53` (same native app source as the passing simulator run).
- `PersonalAssistant-unsigned.ipa` was downloaded to the sibling `PersonalAssistant-iPhone` output folder. It is 10,894,472 bytes and passed checksum/ZIP inspection. Its main executable is ARM64 for physical iOS (Mach-O platform 2), minimum iOS 27.0, version 0.1.0 build 1, bundle ID `dev.jacob.personalassistant`. The Metal library is bundled; model weights and an Apple provisioning profile are absent.
- Package SHA-256: `e8bfcaf58f3dab1b942530dc5d798d954a0a26fd4a65b99e6c77869dd166a21a`.
- Five completed Mac jobs used 23 rounded runner minutes in total. At the published standard Mac rate, compute would be about $1.43 if fully billable. This is an estimate, not a billing-account reading; included usage may cover it. Diagnostic artifacts expire after 7 days and the GitHub device package after 1 day; the local copies are retained. Job evidence is in `Documentation/BuildValidation.json`.

## Historical setup and 0.1 installation

On October 9, 2026, Jacob reported that the privately installed app opens on his iPhone. This establishes the user-reported installation/launch checkpoint. It does not establish successful local inference, sensor accuracy, sustained performance, or readiness for daily use.

Jacob then requested a substantial design phase and a much more mature next device update. The proposal is in `Documentation/PRODUCT_DESIGN.md`. That design pass was followed by the 0.2 implementation recorded above. Model-file reuse, Apple model availability, context/memory behavior, hardware performance, and complete user workflows remain physical validation questions.

Jacob's subsequent design update makes ChatGPT account connection coequal with downloaded models, and explicitly prioritizes native visual polish, real sandbox execution, mature-component reuse, compact prompting, deeper Health/Watch integration, and simple model download/onboarding flows. He reports Private Cloud Compute access; whether this means consumer Apple Intelligence access or an approved developer entitlement remains to be clarified. An optional no-charge hosted workspace is under consideration; no cloud service has been provisioned or connected. Current implementation and signing limits are recorded above.

Apple Devices recognizes the physical iPhone 18 Pro Max over USB and reports iOS 27.0.1. Jacob confirmed that the phone is connected and trusted. Developer Mode was not visible earlier in setup; the agent did not separately inspect its final setting after Jacob reported the app opening.

AltServer 1.8.0 was downloaded from its official distribution, extracted into the thread's tooling folder, and launched. Jacob selected the verified IPA for his phone, but signing stopped with "The provided anisette data is invalid." The helper loaded Apple-signed authentication libraries from its own local cache. The PC clock was checked against Apple HTTPS/NTP responses and was within about two seconds; no clock settings were changed. No provisioning-state files or credentials were read, reset, or deleted.

The PC still has its Microsoft Store Apple Devices and iTunes installations. Apple's desktop iCloud installer was downloaded and its Apple signature verified; its component installers were inspected, but none were installed. Existing Apple applications were not removed or replaced.

Jacob suggested iLoader and explicitly authorized its installation and use. Its documented Windows route supports Microsoft Store iTunes/Apple Devices and direct IPA import. The official stable iLoader 2.3.6 Windows MSI matched GitHub's published SHA-256: `6f0d038f74f60e2e036efa17dd45b7cebd3a4c61b226ff0f03cc8668bb5e3b2d`. A reviewable copy is in the sibling `PersonalAssistant-iPhone/Setup` output folder. Automatic approval review initially rejected combined download/setup execution; after explicit authorization, the MSI ran but returned error 1925 because its machine-wide installation required administrator privileges.

The official EXE installer also matched GitHub's published SHA-256: `747b065996709c0f688323ca1766a21322d31e59ea8be64c24e9bdc70faae632`. Its supported per-user installation succeeded with exit code 0. iLoader 2.3.6 is now running and detects the phone over USB. The running executable is under the Codex Windows package's virtualized local application directory. AltServer was stopped, and the startup entry pointing to this task's AltServer executable was removed. Existing Apple apps remain installed.

Apple sign-in was a user-operated step. After asking about credential safety, Jacob chose his main account and confirmed that sign-in completed. iLoader displayed a signed-in state and the selected USB phone. Only the public 2.3.6 account/storage source was reviewed for the safety question; no password, verification code, credential-vault entry, or pairing-file contents were read. The account code uses the OS keyring when saving a password, and signing material prefers keyring storage with a filesystem fallback if unavailable. This was a focused source review, not a complete security audit. Jacob subsequently reported successful app launch on the phone.

Jacob confirmed he is not enrolled in the paid Apple Developer Program. Enrollment is not needed to write the project or run the shared-core tests.

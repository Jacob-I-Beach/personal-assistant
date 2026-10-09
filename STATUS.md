# Implementation status

This file records implemented features, validation evidence, and user-reported device checks.

## Implemented in source

Portable assistant core, persistent conversations and capture records, normalized provider messages, explicit network authorization, streaming HTTP adapters, read-only capture tool, native camera/OCR/depth capture, SwiftUI screens, Keychain credential storage, MLX download/local-load adapter, capture export/replay, and manual unsigned Mac CI configuration.

## Verification

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

## Next external validation gate

On October 9, 2026, Jacob reported that the privately installed app opens on his iPhone. This establishes the user-reported installation/launch checkpoint. It does not establish successful local inference, sensor accuracy, sustained performance, or readiness for daily use.

Jacob requested a substantial design phase and a much more mature next device update. The proposal is in `Documentation/PRODUCT_DESIGN.md`. No additional device build is being dispatched for this design pass. The next validation questions are model-file reuse, Apple model availability, context/memory behavior, hardware performance, and complete user workflows.

Apple Devices recognizes the physical iPhone 18 Pro Max over USB and reports iOS 27.0.1. Jacob confirmed that the phone is connected and trusted. Developer Mode was not visible earlier in setup; the agent did not separately inspect its final setting after Jacob reported the app opening.

AltServer 1.8.0 was downloaded from its official distribution, extracted into the thread's tooling folder, and launched. Jacob selected the verified IPA for his phone, but signing stopped with "The provided anisette data is invalid." The helper loaded Apple-signed authentication libraries from its own local cache. The PC clock was checked against Apple HTTPS/NTP responses and was within about two seconds; no clock settings were changed. No provisioning-state files or credentials were read, reset, or deleted.

The PC still has its Microsoft Store Apple Devices and iTunes installations. Apple's desktop iCloud installer was downloaded and its Apple signature verified; its component installers were inspected, but none were installed. Existing Apple applications were not removed or replaced.

Jacob suggested iLoader and explicitly authorized its installation and use. Its documented Windows route supports Microsoft Store iTunes/Apple Devices and direct IPA import. The official stable iLoader 2.3.6 Windows MSI matched GitHub's published SHA-256: `6f0d038f74f60e2e036efa17dd45b7cebd3a4c61b226ff0f03cc8668bb5e3b2d`. A reviewable copy is in the sibling `PersonalAssistant-iPhone/Setup` output folder. Automatic approval review initially rejected combined download/setup execution; after explicit authorization, the MSI ran but returned error 1925 because its machine-wide installation required administrator privileges.

The official EXE installer also matched GitHub's published SHA-256: `747b065996709c0f688323ca1766a21322d31e59ea8be64c24e9bdc70faae632`. Its supported per-user installation succeeded with exit code 0. iLoader 2.3.6 is now running and detects the phone over USB. The running executable is under the Codex Windows package's virtualized local application directory. AltServer was stopped, and the startup entry pointing to this task's AltServer executable was removed. Existing Apple apps remain installed.

Apple sign-in was a user-operated step. After asking about credential safety, Jacob chose his main account and confirmed that sign-in completed. iLoader displayed a signed-in state and the selected USB phone. Only the public 2.3.6 account/storage source was reviewed for the safety question; no password, verification code, credential-vault entry, or pairing-file contents were read. The account code uses the OS keyring when saving a password, and signing material prefers keyring storage with a filesystem fallback if unavailable. This was a focused source review, not a complete security audit. Jacob subsequently reported successful app launch on the phone.

Jacob confirmed he is not enrolled in the paid Apple Developer Program. Enrollment is not needed to write the project or run the shared-core tests.

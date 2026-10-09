# Implementation status

This file records validation evidence, not a claim that an iPhone build is installed.

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
- No API key, provider token, or Apple signing credential has been entered.
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

Establish personal signing from Jacob's Windows setup, install the verified device package, then test capture and the downloaded Qwen model on the actual phone. The package is not yet signed or installed. Simulator success does not establish LiDAR accuracy, real-device memory use, thermal behavior, or local-model quality.

The PC has Microsoft Store versions of Apple Devices and iTunes. A Windows signing helper has not been installed or configured. The existing Apple applications were not removed or replaced. Physical USB connection/trust and Apple account sign-in require Jacob's participation.

Jacob confirmed he is not enrolled in the paid Apple Developer Program. Enrollment is not needed to write the project or run the shared-core tests.

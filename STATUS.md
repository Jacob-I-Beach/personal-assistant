# Implementation status

This file records validation evidence, not a claim that an iPhone build is installed.

## Implemented in source

Portable assistant core, persistent conversations and capture records, normalized provider messages, explicit network authorization, streaming HTTP adapters, read-only capture tool, native camera/OCR/depth capture, SwiftUI screens, Keychain credential storage, MLX download/local-load adapter, capture export/replay, and manual unsigned Mac CI configuration.

## Verification

- Official Swift 6.4 Windows toolchain installed and functional.
- All 24 tests passed on Windows using `scripts/Test-Core.ps1 -Integration`: 12 core tests, 5 engine tests, and 7 real-HTTP/loopback tests.
- Cancellation preserves the partial response before the engine becomes idle.
- The HTTP tests exercised both provider protocols, a complete capture-tool loop, interrupted streams, provider failure, HTTP 401, and refused redirects. They used synthetic responses; no external model inference was called.
- All 10 native Swift source files passed a syntax parse. This does not type-check Apple SDK or MLX calls.
- Info.plist parsed successfully; the XcodeGen project and GitHub workflow YAML parsed successfully.
- The MLX Swift LM 3.32.3 and Hugging Face 0.9.0 source interfaces were checked against pinned references.
- No Mac/iOS compile has run yet.
- No physical camera/depth test or local-model benchmark has run yet.
- No API key, provider token, or Apple signing credential has been entered.
- No model weights have been downloaded to this PC.
- The capture replay command was exercised with a synthetic saved observation.
- GitHub CLI 2.102.0 was downloaded to the thread's tooling directory and checked against its official SHA-256 list. It was not installed globally. Jacob completed device authorization for his GitHub account.
- The source is pushed to the private `Jacob-I-Beach/personal-assistant` repository. Repository visibility was verified through GitHub's API.
- The manual Mac workflow uses GitHub's standard `xcode-27` Apple silicon preview image; the `macos-26` image's published inventory does not include Xcode 27.
- Mac validation has not been dispatched. Included Actions allowance could not be verified with the current GitHub login scopes; no account billing settings were changed.

## Next external validation gate

Compile the actual iOS source on an Apple silicon Mac with Xcode 27. The unsigned simulator compile does not need Apple Developer enrollment. Physical installation needs a separate signing workflow.

Jacob confirmed he is not enrolled in the paid Apple Developer Program. Enrollment is not needed to write the project or run the shared-core tests.

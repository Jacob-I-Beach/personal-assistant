# Personal Assistant

A private native iPhone application for Jacob's iPhone on iOS 27. The app owns conversations, observations, and tool execution independently of the selected local or connected model. There is no separate Windows phone UI.

Source repository: [Jacob-I-Beach/personal-assistant](https://github.com/Jacob-I-Beach/personal-assistant).

Jacob confirms that **0.5.0 build 5 opens on his iPhone and preserves his previous chats** (October 10, 2026). ChatGPT account connection is the primary experience; downloaded and Apple on-device models provide offline choices. The app follows [the product design](Documentation/PRODUCT_DESIGN.md), with implemented scope and remaining device checks recorded below.

## Current source: 0.7.1 crash repair

[0.7.1 build 8](Documentation/RELEASE_071.md) repairs the confirmed Reminders callback crash after Save and on relaunch. [Native run 38115961045](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38115961045) passes 161 core and eight EventKit regression tests and builds the iPhone update. Install in place with the same signing account; physical repair confirmation is pending. See [STATUS](STATUS.md).

## 0.7 feature batch

The [0.7 update](Documentation/RELEASE_07.md) is built and verified for personal signing. 0.7 adds bounded working context, readable grouped activity, visible connection retries, correct saved-task cards, continued background CPU/network requests and local attention notifications. The expanded batch adds selected Calendar/Reminders sources, availability checks and reviewed version-checked writes, durable question cards with photo/measurement inputs, routed Inbox capture through the app and Siri/Shortcuts, and Today/Needs-you/Continue/recent outputs on Home.

- A portable Swift core with SQLite transactions, retained legacy JSON migration, full-text history search, bounded working context, and app-owned records.
- Shared app-controlled tools for captures, history, saved memory, actual offline JavaScript execution, editable artifacts, and authorized native Health overviews. External streamed calls are held until terminal completion; native Foundation Models tools use complete validated arguments through the same executor.
- ChatGPT account registration, PKCE/nonce/state checks, JOSE signature verification, separate Keychain registrations, token rotation, account catalogs, and streamed Responses with namespaced tools. Jacob previously verified live account authorization, model loading and a simple response in 0.2; Jacob confirmed the 0.3 Jupiter request with web research and JavaScript completed successfully.
- Ten downloaded MLX choices across Qwen, Granite, Liquid, SmolLM and Gemma, with pinned revisions/sizes/weight hashes, working-memory estimates, and matching-package import through Files. Downloads are separate from inference and do not select or load a model automatically.
- Apple on-device Foundation Models and an entitlement-gated PCC adapter. This is not the complete Siri assistant; a native App Intent exposes the app's own request entry point to Siri/Shortcuts.
- A native conversation interface, rich Markdown/code/tables, model sheet, searchable history, saved-memory editor, artifact previews/revisions, and draft recovery.
- On-device speech transcription where supported and native read-aloud, with interruption and background handling.
- HealthKit sleep/steps/workout overview, calculated overlap handling, missing-data labels, and separate connected-model sharing checks.
- A Watch companion using live plus queued WatchConnectivity delivery, persistent deduplication, visible task states, and manual recovery after interruption.
- Rear AR camera capture, OCR, available LiDAR depth, camera calibration, and camera pose.
- A replay command that runs the same depth-summary code on a saved observation.
- A manual, unsigned Mac CI compile workflow. It has no signing secrets and does not publish an app.

**Current verified package: 0.7.0 build 7.** The final [native validation](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38113083813) passed 161 core tests and the streaming interaction check. [Baseline run 38111714194](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38111714194) passed all 22 platform checks and the other 14 interface scenarios on identical production app code. Only a DEBUG-only streaming fixture timing changed. All 15 UI scenarios have passing coverage; this is not a claim that one final run repeated all 15. The [Release device build](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38113083813) matches source `cc5f8c432bfeb3226db6f041285e853370af9422`.

The sibling `PersonalAssistant-iPhone/0.7.0` folder contains the iPhone-only IPA and installation instructions. Phone installation and live permissions remain pending.

**Installation scope:** official iLoader 2.3.6 does not provision the Watch companion or request HealthKit for this app. Use **PersonalAssistant-iPhone-only.ipa**, keeping the existing app and the same account. The full compiled archive is retained for a compatible signing route. Health remains clearly unavailable in this profile. Follow the [manual installation and device checks](Documentation/DEVICE_VALIDATION.md).

## Run meaningful tests on Windows

Install the official [Swift Windows toolchain](https://www.swift.org/install/windows/) if needed. Visual Studio C++ Build Tools and a compatible Windows SDK are prerequisites. The Swift installer may add its supported Python runtime.

```powershell
powershell -File scripts/Test-Core.ps1 -Integration
```

This starts a temporary loopback-only synthetic SSE server, compiles the real shared Swift code, and checks persistence, tool authorization, interrupted streams, model switching, and the HTTP transport. The server is stopped afterward. These are implementation tests, not LLM-quality or phone-performance benchmarks.

The Swift 6.4 Windows build can emit a warning about its optional `.build/debug` symlink when Windows Developer Mode is disabled. The tests do not require changing that setting when they otherwise pass.

## Compile the actual app on a Mac

Use an Apple silicon Mac with Xcode 27 and a compatible macOS version:

The manual GitHub workflow selects the standard `xcode-27` preview runner, which includes the iOS 27 SDK. It runs only on explicit dispatch, with a 20-minute full-suite timeout (15 minutes for a focused repair backed by matching prior UI evidence). A push does not start a build. Private-repository Actions usage can incur charges beyond the account's included allowance.

```bash
brew install xcodegen
xcodebuild -downloadComponent MetalToolchain
xcodegen generate --spec project.yml
mkdir -p PersonalAssistant.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp Dependencies/Package.resolved PersonalAssistant.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
xcodebuild -project PersonalAssistant.xcodeproj -scheme PersonalAssistant \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData -skipMacroValidation CODE_SIGNING_ALLOWED=NO build
```

The project specification pins MLX and Hugging Face package releases. `Dependencies/Package.resolved` retains the full dependency resolution obtained on the Mac. The generated Xcode project is derived from `project.yml`. The scoped macro-validation flag permits the pinned model-library macros to run without Xcode's interactive prompt.

The manual workflow compiles the phone and Watch targets, runs native authorization and interface tests, and saves screenshots. It does not download a model or make a paid inference call. Verbose simulator diagnostics are disabled because they stalled for 600 seconds after otherwise successful tests; result bundles, ordinary logs, and screenshots are retained.

The optional `build_device` input builds a Release package for physical iPhone hardware and records its SHA-256. An ad-hoc seal records requested entitlements; it is not installable Apple signing, and a signing tool must actually provision the capabilities it enables. `PersonalAssistant-unsigned.ipa` contains both phone and Watch. `PersonalAssistant-iPhone-only.ipa` omits the unsupported Watch directory for the existing iLoader route and retains the exact same iPhone executable. Both are inspected for identity, platform, kernels, and integrity. No Apple signing credentials are sent to CI.

For physical installation, open the generated project in Xcode, select your own signing team, choose the iPhone, and enable Developer Mode when iOS requests it. No paid Apple Developer membership has been assumed or purchased. Free Personal Team signing has limitations and seven-day provisioning; hosted signing needs a separately established credential/provisioning route.

## First device test

1. Open Models and choose an available Apple model, connect ChatGPT, or download/import the selected MLX model. A model is never downloaded implicitly by sending a message.
2. Load a short text conversation, interrupt a response, reopen the app, and verify the saved transcript.
3. Capture a scene or import one selected image. Open Captures to inspect its recognized text and available depth.
4. Attach the capture and ask the model to use `read_capture` to report what was actually recorded.
5. Configure a PC endpoint or an OpenAI API model only if desired. The app requests permission before sending that conversation and its attachments to the configured destination.
6. Run the same question through that model and verify that the saved capture and tool result remain the same.

The MLX provider uses the vision-model factory. Arbitrary repository compatibility is not promised. The stored transcript is independent from the current context budget; exact history and user-edited memories can be retrieved. Generic context budgeting is conservative and not a claim of exact per-provider token counting. Models still require physical memory, thermal, latency, and tool-reliability measurements.

## Provider access

- **Downloaded model:** weights and tokenizer are stored in the app's Application Support directory. Inference reloads from local files, not a network model service.
- **OpenAI API:** supports an API key saved in device-only Keychain. This is separate from a ChatGPT subscription and can incur provider charges. No key is included in this repository.
- **PC / compatible server:** provide an OpenAI-compatible `/v1` endpoint and model identifier. Use HTTPS except for explicitly configured private LAN/loopback addresses.
- **Sign in with ChatGPT:** uses the documented local-app registration and inference route. Jacob has verified account authorization, model loading and live inference. Per-model feature availability remains account-dependent. It does not import ChatGPT's existing conversations, memory, hosted Code Interpreter, or Health permissions.
- **Apple models:** on-device availability is queried through Foundation Models. Direct PCC requires the app's managed entitlement, not merely consumer Siri/iCloud access.

Changing models preserves the app-owned conversation. Provider-specific opaque continuation items are reused only with the exact original provider/model; they are not handed to a different provider.

## Capture semantics

`observation.json` stores OCR, timestamps, camera pose/intrinsics, and an optional downsampled depth grid. `image.jpg` is normalized for display. The depth grid and intrinsics remain in the native sensor orientation; the record identifies the display rotation and native sensor-image dimensions.

The current measurement is only a median depth in the center of the saved grid, excluding low-confidence samples where confidence is available. It is **not** object size, a calibrated accuracy interval, a live reading, or evidence about hidden surfaces. Front TrueDepth, RoomPlan, object tracking, and arbitrary measurements are later tools.

To inspect an exported observation on Windows or macOS:

```bash
swift run capture-replay /path/to/observation.json
```

## Data boundaries

- Private application data and model files remain in the application container and are excluded from device backups by default. Verified generated copies in Documents/Outputs are intentionally visible in Files; their backup/synchronization follows the chosen location/provider.
- The app does not synchronize its private conversation database with a developer server. A user-selected external folder or export destination can be managed by iCloud or another Files provider; a local save receipt does not confirm that provider's cloud synchronization.
- Network-model permission is scoped to a conversation and the configured destination.
- Credentials are stored in Keychain, not conversations, settings JSON, or model prompts.
- HTTP redirects are rejected for model requests.
- Model-supplied tool names and arguments are checked by ordinary code. JavaScript runs in a fresh bounded interpreter without host filesystem/network APIs or bytecode loading.
- Notes marked for on-device models are omitted from connected-model context. Their derived messages and artifacts retain a local-only classification; protected history cannot be recovered through a remote model's search/read tool.
- Health-derived context has an additional destination permission. A library containing Health data remains excluded from device backup; export of selected items is a separate explicit user action.
- Camera access starts from a user-opened capture view and stops when that view closes.

## Remaining product work

Conversation branching, richer artifact formats/editing, general PC/cloud execution, reliable native background jobs, broader organizer integrations, advanced sensor workflows, Core AI comparisons, and measured local-model tuning remain in the product design. A no-charge cloud workspace is a candidate, not a provisioned service. The current Watch uses the phone for reasoning; it does not promise an always-awake phone GPU.

No public-app marketplace, billing system, multiuser server, or Windows imitation UI is included.

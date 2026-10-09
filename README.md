# Personal Assistant

A private native iPhone application for Jacob's iPhone on iOS 27. The app owns conversations, observations, and tool execution independently of the selected local or connected model. There is no separate Windows phone UI.

## Current implementation

- A portable Swift core with app-owned persistent conversations and capture records.
- An assistant loop that records tool results and requires explicit model completion before executing a tool.
- Streaming OpenAI Responses and OpenAI-compatible Chat Completions adapters.
- An MLX adapter for downloaded vision-language models, initially Qwen3.5-4B.
- A native SwiftUI interface for conversation history, capture inspection, model settings, and cancellation.
- Rear AR camera capture, OCR, available LiDAR depth, camera calibration, and camera pose.
- A read-only `read_capture` tool restricted to captures attached to the conversation.
- A replay command that runs the same depth-summary code on a saved observation.
- A manual, unsigned Mac CI compile workflow. It has no signing secrets and does not publish an app.

**Validation boundary:** Windows can compile and test `AssistantCore`; it cannot compile UIKit, ARKit, or MLX for iPhone. A successful Mac compile and physical-phone test are still required before claiming the iOS app works. See [STATUS.md](STATUS.md) for the checks actually completed.

## Run meaningful tests on Windows

Install the official [Swift Windows toolchain](https://www.swift.org/install/windows/) if needed. Visual Studio C++ Build Tools and a compatible Windows SDK are prerequisites. The Swift installer may add its supported Python runtime.

```powershell
powershell -File scripts/Test-Core.ps1 -Integration
```

This starts a temporary loopback-only synthetic SSE server, compiles the real shared Swift code, and checks persistence, tool authorization, interrupted streams, model switching, and the HTTP transport. The server is stopped afterward. These are implementation tests, not LLM-quality or phone-performance benchmarks.

The Swift 6.4 Windows build can emit a warning about its optional `.build/debug` symlink when Windows Developer Mode is disabled. The tests do not require changing that setting when they otherwise pass.

## Compile the actual app on a Mac

Use an Apple silicon Mac with Xcode 27 and a compatible macOS version:

```bash
brew install xcodegen
xcodegen generate --spec project.yml
xcodebuild -project PersonalAssistant.xcodeproj -scheme PersonalAssistant \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

The project specification pins MLX and Hugging Face package releases. Keep the resolved dependency lockfile produced by the first successful Mac resolution. The generated Xcode project is derived from `project.yml`.

For physical installation, open the generated project in Xcode, select your own signing team, choose the iPhone, and enable Developer Mode when iOS requests it. No paid Apple Developer membership has been assumed or purchased. Free Personal Team signing has limitations and seven-day provisioning; hosted signing needs a separately established credential/provisioning route.

## First device test

1. In Settings, save the local model settings and explicitly download the selected model on Wi-Fi. The model is not downloaded automatically during chat.
2. Load a short text conversation, interrupt a response, reopen the app, and verify the saved transcript.
3. Capture a scene or import one selected image. Open Captures to inspect its recognized text and available depth.
4. Attach the capture and ask the model to use `read_capture` to report what was actually recorded.
5. Configure a PC endpoint or an OpenAI API model only if desired. The app requests permission before sending that conversation and its attachments to the configured destination.
6. Run the same question through that model and verify that the saved capture and tool result remain the same.

The first MLX provider uses the vision-model factory. The Qwen baseline supports images and text; arbitrary repository compatibility is not promised. The pinned model revision is recorded in the default settings. Generation has a configurable response budget; long-term memory retrieval and context compaction are not implemented yet.

## Provider access

- **Downloaded model:** weights and tokenizer are stored in the app's Application Support directory. Inference reloads from local files, not a network model service.
- **OpenAI API:** supports an API key saved in device-only Keychain. This is separate from a ChatGPT subscription and can incur provider charges. No key is included in this repository.
- **PC / compatible server:** provide an OpenAI-compatible `/v1` endpoint and model identifier. Use HTTPS except for explicitly configured private LAN/loopback addresses.
- **Sign in with ChatGPT:** not implemented in this first source increment. Its account eligibility, iOS callback flow, model catalog, and custom-tool wire format need a dedicated integration. No fake sign-in button is present.

Changing models preserves the app-owned conversation. Provider-specific opaque continuation items are reused only with the exact original provider/model; they are not handed to a different provider.

## Capture semantics

`observation.json` stores OCR, timestamps, camera pose/intrinsics, and an optional downsampled depth grid. `image.jpg` is normalized for display. The depth grid and intrinsics remain in the native sensor orientation; the record identifies the display rotation and native sensor-image dimensions.

The current measurement is only a median depth in the center of the saved grid, excluding low-confidence samples where confidence is available. It is **not** object size, a calibrated accuracy interval, a live reading, or evidence about hidden surfaces. Front TrueDepth, RoomPlan, object tracking, and arbitrary measurements are later tools.

To inspect an exported observation on Windows or macOS:

```bash
swift run capture-replay /path/to/observation.json
```

## Data boundaries

- Data and model files are kept inside the application container and excluded from device backups by default.
- The current app does not synchronize with iCloud or any developer server.
- Network-model permission is scoped to a conversation and the configured destination.
- Credentials are stored in Keychain, not conversations, settings JSON, or model prompts.
- HTTP redirects are rejected for model requests.
- Model-supplied tool names and arguments are checked by ordinary code. The only current tool reads an explicitly attached capture.
- Camera access starts from a user-opened capture view and stops when that view closes.

## Deliberately later

Watch companion, speech conversation, semantic memory/retrieval, code sandbox, account-based model picker, Core AI optimization, additional sensor tools, and background tasks. These belong in this same product, but are not represented as working in this first increment.

No public-app marketplace, billing system, multiuser server, or Windows imitation UI is included.

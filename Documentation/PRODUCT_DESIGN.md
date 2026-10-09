# Personal Assistant product design

Design proposal dated October 9, 2026. This is the working specification for discussion and the next substantial device release. It describes intended behavior; it does not represent the listed features as implemented. Jacob has reported that the first private build installs and opens on his iPhone.

The product is a private assistant that Jacob can talk to, show things, give documents, and ask to complete useful work. Conversations, knowledge, actions, and results belong to the app. The selected model supplies reasoning and generation within that system. Phone-local operation is the primary experience; a PC or cloud model extends it when deliberately selected.

## 1. Direction and release policy

The next installed version should be a coherent daily-use product. A better-looking settings screen or another isolated tool does not meet that bar. We will design and validate the connected workflows first, accumulate related implementation work, and package a release when those workflows meet the acceptance criteria below.

Internal iterations remain small enough to test and diagnose. This does not require Jacob to reinstall after each change. Windows tests exercise portable logic and provider protocols; Mac builds check the actual native app; simulator tests exercise real screens. Physical-phone tests address questions that those environments cannot answer. Any additional device build before the substantial release should have a specific engineering purpose agreed with Jacob.

Requirements already established by Jacob:

- Private use on his devices, with no public-product, marketplace, advertising, subscription-selling, or multiuser infrastructure scope.
- Native iPhone experience, with a planned Apple Watch companion. Current phone is an iPhone 18 Pro Max running iOS 27.0.1.
- Downloaded models are first-class. The design must not impose an arbitrary small-model ceiling.
- PC inference and cloud models use the same conversations, memory rules, tools, and artifacts.
- Avoid repeated downloads, repeated setup, unnecessary migrations, and a separate Windows imitation of the phone interface.
- Prefer meaningful capability and reliability over a large catalog of barely functioning features.

The design borrows useful product principles: native integration and restraint; natural multimodal conversation; durable, editable work products; strong retrieval and continuity across devices. These are design goals for our own product, not a promise to inherit another assistant's proprietary features.

## 2. The existing Qwen download and Apple model options

### Reusing Qwen

The installed prototype has a download-and-load path for its own MLX model directory. It has no model-import UI and cannot automatically adopt another app's cache. Therefore, the current build would download its own copy.

Locally AI describes itself as MLX-based, which makes compatible-file import a credible route. It does not establish that Jacob's particular download is exportable or that it matches our runtime. We need the model's accessible files, configuration, tokenizer, quantization details, and any vision resources. [Locally AI](https://locallyai.app/)

iOS gives each app its own sandbox. Another app's private model cache is not a shared system model library. Reuse must go through a supported export, Files selection, or another explicit sharing mechanism. Developer Mode does not remove that boundary. [Apple sandbox model](https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web)

The next model manager will support importing a compatible MLX folder or package, validate the complete file set, and explain missing or unsupported components. It will distinguish avoiding another internet download from avoiding a second on-device copy. Opening a user-selected Files location in place is an optional optimization only after bookmark persistence, provider availability, memory mapping, and failure recovery work reliably. A self-contained copy is the safer default for a model needed offline.

We will not add another inference engine merely to accept a filename. GGUF support is a separately validated runtime adapter if actual model needs justify it. A GGUF file cannot be treated as an MLX checkpoint by renaming it.

### Apple and Siri

The model picker should offer Apple Intelligence on-device when the system reports it available. It should display the actual model variant returned by the OS, such as AFM 3 Core or AFM 3 Core Advanced, rather than inventing a fixed model identity. Apple manages these assets; our app does not need its own duplicate download. System readiness, device eligibility, locale, and OS model version still matter. [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), [Variant](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/variant-swift.struct)

Using that model is distinct from embedding the complete Siri assistant. The public integration makes our actions and content available to Siri through App Intents, entities, schemas, Spotlight indexing, and view annotations. It does not automatically grant our app Siri's access to unrelated apps. [Apple Intelligence and Siri AI](https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai)

Apple also exposes Private Cloud Compute through Foundation Models. It has a separate eligibility and entitlement gate: Apple currently lists Small Business Program enrollment, fewer than two million first-time App Store downloads, and an assigned entitlement. Eligible testing includes TestFlight or ad hoc distribution. Our current free personal-signing setup must not assume this access. It is a conditional future provider, not a promised working selector entry. [PCC eligibility](https://developer.apple.com/private-cloud-compute/)

## 3. The main experience

The default screen is a conversation with a clear current project, a compact model selector, and a composer that accepts text, voice, camera input, and files. A person should be able to start asking useful questions without entering a repository identifier, revision hash, endpoint URL, or token budget. Advanced controls remain available behind model details.

Proposed navigation:

| Surface | Purpose |
| --- | --- |
| Assistant | Conversations, voice, attachments, and the current task |
| Library | Projects, documents, captures, saved memories, and created artifacts |
| Activity | Running, queued, interrupted, and completed tasks, including their results |
| Model picker and settings | Models, connected providers, permissions, storage, and diagnostics |

History belongs in a searchable conversation/project browser. It needs rename, archive, pin, search, and clear deletion behavior. A long menu of conversation titles will not scale.

The composer should keep drafts when a send fails, distinguish a queued message from a sent one, allow attachments to be inspected before sending, and preserve keyboard focus predictably. The interface should support Markdown, code blocks, tables, accessible text selection, copy, share, reply, edit-and-branch, and regenerate. Editing an earlier prompt creates a branch so previous work remains accessible. Switching models changes subsequent work and preserves the record of which model produced earlier answers.

Streaming must not drag the user to the bottom while they are reading an earlier message. A return-to-latest control appears when needed. VoiceOver, Dynamic Type, reduced motion, contrast, one-handed reach, and interrupted keyboard/audio sessions are acceptance requirements.

A compact activity card should say what the app is actually doing: loading a model, reading a document, searching, calculating, waiting for permission, or writing a result. Technical details expand on request. The app should not manufacture a reasoning transcript or pretend that an animated checklist proves work occurred.

## 4. Model selection and model management

The picker groups available choices by where inference runs:

- On this iPhone: downloaded models and the available Apple system model.
- On my computer: paired model endpoints and their live catalog.
- Connected services: supported account-authorized or API-backed providers.

Each entry identifies its real location, readiness, supported modalities, tested tool behavior, and practical context setting. Download size, disk use, estimated working-memory class, and measured performance belong in details. A model being supported by a library is different from being tested on this phone; show that distinction explicitly.

The library supports resumable download, import, verification, cancellation, removal of weights without deleting conversations, and repair of incomplete packages. It records source, revision, format, file hashes, tokenizer/template, quantization, vision components, and runtime compatibility. A model name alone is insufficient identity. Arbitrary repository code is never executed merely because a model configuration requests it.

The initial downloaded-model runtime remains MLX because it is already compiled into our app and fits the selected Qwen baseline. Larger compatible models can be offered after measuring their working set and usability. Parameter count and 1 TB of storage do not determine whether a model fits in active memory.

Apple's Core AI is a second optimization path to evaluate, rather than a reason to rewrite a working MLX provider in advance. Its export recipe and chosen execution engine affect whether CPU, GPU, or Neural Engine is used. We should compare a supported model on the phone before adopting a conversion pipeline. [Core AI integration](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session)

An Automatic setting, if included, must have a visible policy. Local-only mode remains a hard constraint. A quality or speed preference can change permitted local choices, but never silently moves a private request to a server. A manually pinned model stays pinned until the user changes it or accepts a fallback.

## 5. Conversation history, context, and memory

Three different things need distinct designs:

1. The durable record: complete messages, sources, actions, results, and artifacts stored by the app.
2. The current model context: the limited material supplied for a particular request.
3. Saved memory: selected information intended to remain useful across conversations.

There should be no arbitrary short conversation cap. A conversation can keep growing in storage while the app assembles an appropriate working context for each model. That does not create an infinite model context window or guarantee perfect recall.

The context planner budgets instructions, selected tools, the current request, recent turns, pinned material, retrieved evidence, images, and room for the answer. It uses actual tokenizer counts where available. A fallback estimate must be identified internally and remain conservative. If essential material does not fit, the app can read it in sections, narrow the scope, or offer another permitted model.

Older material remains intact. Rolling summaries help orient the model, but source messages and documents remain searchable and retrievable. Exact quotations, dates, quantities, and conflicting claims should be rechecked against source passages. Images should be loaded only when relevant, with cached processing keyed to the image and runtime; every old image must not be re-encoded on every turn.

Proposed memory categories:

| Kind | Example | Expected behavior |
| --- | --- | --- |
| Explicit personal memory | A preference Jacob asks the app to remember | Editable and deletable, with its source |
| Project knowledge | Documents, requirements, decisions, and terminology | Scoped to that project by default |
| Working state | Current plan, unresolved questions, completed steps | Resumable and clearly temporary |
| Saved observation | A photograph, OCR result, or sensor reading | Timestamped evidence, not a current fact |
| Inferred suggestion | A pattern the model thinks may be useful | A suggestion for review, not an unquestioned personal fact |

A memory record should include provenance, scope, time, confidence or confirmation state, superseded records, and allowed processing locations. A preference changed today should supersede an older preference without deleting the historical conversation. The app must not infer sensitive personal characteristics and quietly promote them to permanent memory.

The person can ask what is remembered, why a memory was used, correct it, or exclude a conversation from memory. Forgetting should invalidate derived retrieval entries and summaries that would otherwise reintroduce the same memory. Deleting a source and merely removing a saved preference are separate operations that need plain explanations.

Embedding indexes are rebuildable derived data, not the only copy of knowledge. Index entries must retain source ranges and embedding-model identity. Switching embedding models requires reindexing or separate indexes, not mixing incompatible vectors.

## 6. Tools and actions

The model proposes actions; ordinary app code controls whether and how they execute. Every tool declares its input/output schema, required capability, permitted data scope, execution location, network use, side effects, cancellation behavior, and retry policy.

Start with a small useful set that completes real tasks:

| Tool family | Initial useful operations | Important boundary |
| --- | --- | --- |
| Knowledge | Search a project, read a source range, retrieve a saved capture | Only the selected scope |
| Calculation | Arithmetic, units, dates, tables, and small data transformations | Deterministic computation with checked inputs |
| Web | Search, fetch a page, extract useful text, retain citations | Network use is visible even with a local model |
| Documents | Read supported files, extract text/OCR, create or revise an artifact | Originals remain intact unless an edit is confirmed |
| Camera | Capture or select evidence, OCR, barcode reading, supported depth analysis | Active capture is visible and user-directed |
| Organizer | Authorized calendar/reminder reads and staged changes | Resolve ambiguity before writing |
| PC | Requests to explicitly exposed companion tools or a bounded code environment | A paired PC has its own permissions |

The tool catalog should expose only relevant schemas to a small-context model. Tool selection is an app-side capability; it must not depend on a provider offering hosted tool-search features. A tool result cannot grant itself more authority or override the user's instruction.

Routine read-only actions over data deliberately supplied to the task should not demand repetitive confirmations. Sending, purchasing, deleting important data, changing sharing, or making an ambiguous external edit should present the exact proposed action at the point of commitment. A confirmation applies to that action and scope, not to a model's entire future plan.

The app records receipts: what ran, against which source or destination, with which result. A timeout after an external write is an uncertain outcome, not permission to repeat the write. Prefer idempotency keys where the service supports them; otherwise check the result before retrying.

## 7. Research and editable work products

Research is a workflow: clarify the question when necessary, select sources, fetch material, extract evidence, compare it, calculate where appropriate, and produce a result with citations. Search snippets are leads, not substitutes for reading a source.

The library retains source URLs, titles, retrieval times, source ranges, and derived notes. Cached content is labeled when stale. A local model can use web tools, but that task is network-assisted; the UI must distinguish local inference from an entirely offline workflow.

Substantial outputs become artifacts: a document, table, checklist, code file, diagram, or small interactive tool. Each artifact has its own identity and revisions, and remains linked to the conversation and sources that produced it. The user can edit a selected passage directly or ask for a targeted revision. A new revision should not erase unrelated manual edits.

Claude's artifact experience is a useful reference for treating outputs as editable work that survives the chat. Our implementation will keep those objects in our own storage and support appropriate local formats. [Artifact reference](https://support.claude.com/en/articles/17153992-what-are-artifacts-and-how-do-i-use-them)

Initial exports should cover the formats we can produce reliably, such as Markdown, plain text, CSV, PDF, and supported images. Editable office formats can follow validated generation paths rather than being promised because a model can emit XML. Interactive previews need their own content restrictions; generated HTML must not inherit access to the app's files, cookies, or credentials.

## 8. Local code execution

There are two useful tiers:

- Phone execution for bounded calculations, parsing, table transforms, and small generated utilities.
- Optional PC execution for heavier Python/package workloads and larger datasets.

The phone design should use a constrained interpreter or a suitable interpreter-based WebAssembly runtime with enforced instruction, memory, output, and wall-time limits. Its filesystem is a deliberately supplied virtual workspace, and network access is absent by default. It exposes no arbitrary native bridge.

A background thread, a temporary folder, or a promise timeout is not a sufficient sandbox. We must demonstrate that a nonterminating program can actually be stopped without freezing the app and that it cannot read unrelated data. Until that passes, the product should offer verified calculation tools and accurately label broader execution as unavailable.

The PC executor should use a real isolated environment, scoped input mounts, bounded outputs, and explicit network permissions. The phone shows that code ran on the PC. A paired computer must not turn every model request into unrestricted desktop authority.

Full Python on the phone is a feasibility experiment, not a release promise. The experience we want is useful computation with inspectable results; the runtime language is a means to that end.

## 9. Voice and visual interaction

The initial voice experience combines local speech recognition where supported, the selected model, and speech output. It should retain an editable transcript, support interruption, respond to headphones and audio-route changes, and recover after a call or app interruption. Wake-word listening and continuous recording are separate designs with separate battery and permission consequences.

Voice should continue the same conversation as typing. Interrupting an answer stops speech and generation while preserving the partial result honestly. Long responses can offer a short spoken answer with a more complete written result. A tool's completion can be announced without reading a long diagnostic receipt aloud.

Live camera mode uses an explicitly opened session. A user can point, ask, freeze a frame, select a region, and continue the conversation. The system labels whether it is discussing a current view, a frozen snapshot, or a remembered capture. It throttles frame processing and retains only the evidence the user chooses to keep.

Visual perception is a pipeline: image capture, useful crops, OCR/barcodes, model interpretation, and separately computed measurements when supported. Depth, camera calibration, pose, and tracking quality should be preserved together. An object dimension requires a valid measurement method and quality checks; the prototype's center-depth median is not an object measurement.

Rear camera and LiDAR are the first sensor workflow to improve. TrueDepth can be explored through public depth/AR APIs after that pipeline is reliable. Face ID authentication can protect access to the app, but it does not give the model the protected Face ID enrollment data or unrestricted raw infrared access.

Native-audio cloud providers are optional later adapters. Provider reconnect and session expiry must not erase app-owned context. Google's Live API session design is a useful reference for treating a voice session as resumable even when an underlying connection ends. [Live session management](https://ai.google.dev/gemini-api/docs/live-api/session-management)

## 10. Apple ecosystem integration

The phone app should expose a small, coherent set of App Intents: start or continue a conversation, capture an observation, add something to a project, and run a saved bounded workflow. The same actions can support Siri, Shortcuts, widgets, and applicable system controls. Content made discoverable to the system must respect the user's privacy choices.

A Share extension should accept selected text, links, images, and documents into an inbox or a chosen project. Files import and export remain useful independently. Shared containers, extension signing, and app-group entitlements must be validated under the actual signing method before the extension becomes a release commitment.

The Watch should be a quick interaction surface for the same assistant: dictate a short request, capture a thought, view a concise answer, inspect task status, and continue on the phone. Expensive model work should initially remain on the phone or another explicitly chosen backend. Requests carry stable IDs so queued delivery or retries do not perform an action twice.

WatchConnectivity supports background transfers and live exchanges under different conditions. Therefore a Watch request needs visible states such as sent, waiting for phone, and ready; it must not promise an instantly available phone GPU while iOS has suspended the app. [WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity)

HealthKit, workouts, HomeKit, location, motion, Bluetooth accessories, and NFC are potential scoped tool families. Add a family when it serves a specific desired workflow and its authorization, data semantics, and signing requirements are understood. The app should not request every possible permission at first launch.

Ordinary public APIs do not provide a universal feed of all notifications, iMessage history, every app's files, or Siri's private personal-context store. Integration should use supported framework access, deliberate sharing, registered actions, and authorized service connectors. The private nature of this project does not change those technical boundaries.

## 11. Background work and automation

Useful triggers include a shared document, an App Intent, a Watch request, a user-started research task, or an explicitly configured event. A trigger produces a task with a defined purpose, data scope, execution budget, and completion condition.

iOS supports continuing certain user-started work through BGContinuedProcessingTask. Submission starts from the foreground in response to an action. GPU use needs both device support and the Background GPU Access entitlement, and tasks can expire or be canceled. The design must checkpoint and recover rather than assume perpetual execution. [Background task behavior](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)

Task states should distinguish queued, active, awaiting input, awaiting permission, waiting for network or device, interrupted by the system, canceled, failed, and complete. A local notification can invite the user to resume work that cannot continue unattended. It must not claim a scheduled task ran when the OS never granted execution time.

Persistent off-phone schedules belong on an explicitly configured PC or service. The phone should show where the work will run and what data that location can access. A background audio mode, fake workout, or other unrelated entitlement is not an acceptable way to keep a general assistant alive indefinitely.

## 12. Hardware and model performance

The performance objective is the best useful intelligence at an acceptable interaction speed, temperature, and battery cost. It does not require keeping every accelerator busy simultaneously.

The runtime estimates and then measures the full working set: weights, KV cache or other model state, vision/audio components, prompt processing buffers, UI assets, and headroom for iOS. It admits a model only when the configuration is plausible, then records what happened on the actual device. A storage-capacity figure is not a RAM budget.

Proposed policies:

- Keep one heavy local generation or prefill active at a time by default.
- Reuse a valid warm session/cache when it improves latency, tied to the exact model and conversation state.
- Release inactive models and stale image tensors before loading a different large model.
- Prioritize UI responsiveness, voice capture, and Stop over indexing or background summaries.
- Reduce work or checkpoint when the system reports thermal or memory pressure.
- Offer explicit choices when a workload needs a smaller context, another local model, or an authorized off-phone backend.

Measure cold start, first-token latency, sustained generation, long-context prefill, image processing, cancellation, memory pressure, and a repeated ten-minute workload. Numerical performance promises come after measurements. A benchmark from a Mac or a different phone is not evidence for this device.

MLX remains a valid Metal-based runtime. Apple system models, Vision, speech, and a future Core AI adapter can use Apple's optimized facilities through their supported interfaces. We should not add an ANE toggle that cannot actually control the selected runtime.

## 13. Cloud accounts and the PC

Connections are separate from the app's identity. Jacob can use the assistant locally without signing into a vendor. A cloud connection adds that provider's available models and its own usage limits, not ownership of the app's conversations or memory.

OpenAI now documents a ChatGPT-plan authorization path for open-source and locally hosted apps. It is distinct from identity-only website sign-in. It uses OAuth, a registered client and host identity, and a loopback callback; a reliable native iOS authorization flow still needs to be proven. This is a planned integration with a feasibility gate, not a claim that our current app has it. [ChatGPT plan integration](https://developers.openai.com/siwc/token-sharing-open-source)

That route does not import ChatGPT conversations or account context. Its preview also does not supply every ChatGPT capability: hosted Code Interpreter, file search, image generation, and audio/video APIs are among the documented exclusions. Our own memory, tools, artifacts, speech pipeline, and retrieval therefore remain essential. Available models and capabilities must be fetched through the supported provider route. [Preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)

Claude and Gemini connections need their own supported authentication and API contracts. A consumer subscription must not be treated as a universal API key. Ordinary API adapters remain a practical option, with visible usage and explicit configuration.

PC pairing should use an authenticated channel and a clear identity, not an unauthenticated endpoint exposed to the internet. Model inference, file access, and code execution are separate grants. A PC model can contribute better reasoning while tools still execute on the phone; a phone model can use an authorized PC calculation tool. The UI shows both locations when they differ.

## 14. Privacy, ownership, and recovery

Local-only must be enforced in the request and tool layers, not just displayed as a badge. Web access, cloud inference, external connectors, and diagnostics have separate data consequences. Permission to use a cloud model for one conversation does not automatically authorize sending every saved memory or library document.

Each context item carries its source, scope, sensitivity setting where supplied, and allowed destinations. The context planner and tool broker enforce those properties. Retrieved web pages and documents are untrusted content; instructions inside them do not become authority to send, delete, or execute.

Use device-protected storage and Keychain for credentials. Keep pairing credentials, provider tokens, and signing material out of prompts and logs. Offer an app lock for sensitive material without pretending that a UI lock replaces file protection.

Separate replaceable model weights from irreplaceable user data. The prototype excludes its whole support directory from backup; the next design needs deliberate backup/export behavior for conversations, memories, original evidence, and artifacts. Model weights can remain excluded. Any cloud backup or sync is an explicit choice with its own recovery behavior.

The first durable storage upgrade should provide transactions, efficient incremental writes, schema migrations, source indexes, and repair/export. A transactional SQLite implementation behind a portable storage interface is the proposed direction. The full transcript and source files remain authoritative; summaries, embeddings, and model caches can be rebuilt.

Updates must preserve the effective installed bundle identity and data container. Migration should keep a recoverable copy, detect interruption, and avoid requiring app deletion. Signing renewal and code updates should not trigger new model downloads. A redacted diagnostic export should make failures understandable without including credentials or whole personal conversations by default.

## 15. Architecture and what we retain

The durable app data, context planner, task coordinator, permission checks, tool services, and artifact store form the assistant's core. Native UI, voice, camera, Watch, and App Intents are ways into that same core. Providers sit behind an adapter boundary.

Conceptual flow:

Input or event → task and context plan → selected model → proposed tool call → permission and validation → tool result → updated answer or artifact → durable checkpoint.

The current code already has useful foundations: provider-independent records, structured tool calls, refusal to execute incomplete calls, streaming parsers, cancellation checkpoints, endpoint checks, Keychain credentials, and tests around failure paths. Keep and strengthen them.

The current limits that need deliberate redesign are concrete:

| Current behavior | Next design |
| --- | --- |
| Raw repository/revision and endpoint fields are the main model interface | A catalog, import flow, connection flow, and advanced details |
| The engine builds a request from the whole transcript and all attached images | A token-aware context planner and targeted evidence retrieval |
| A new MLX chat session is created for each request | Managed session/cache lifetime with explicit invalidation |
| Whole JSON records are rewritten during generation | Transactional incremental persistence and a migration path |
| Messages are primarily plain text | Rich conversation rendering and durable editable artifacts |
| History is a menu | Searchable conversations and projects |
| There is one read-only capture tool | A tested tool system with scoped capabilities and action receipts |
| No semantic memory, voice pipeline, or Watch companion | Shared services with native entry points and explicit limits |

The iOS 27 Foundation Models protocol and Dynamic Profiles can reduce provider-specific work on Apple platforms. We should use those APIs where they help while retaining app-owned records and tool authority. We do not need two independent agent loops competing to own the same task. [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels)

## 16. Workflows that define the next release

### A long-running project

Start with a document and a few requirements. Discuss it over many sessions, change one requirement, switch between permitted models, close and reopen the app, and ask for the current decision. The answer should retrieve the right source, prefer the updated requirement, and preserve earlier work. The person can inspect and correct what the app remembered.

### Research that produces useful work

Ask for a comparison using current sources and a supplied table. The assistant searches and reads sources, calculates totals through a deterministic tool, produces an editable comparison, and revises one part without rewriting everything. Sources and assumptions remain inspectable. A disconnected network preserves completed work and makes the missing step clear.

### Show and ask

Capture an object or document, select the relevant region, and ask a question. OCR, image interpretation, and any measured depth remain distinguishable. The app can retrieve the saved capture later without describing it as a live camera view. A bad or ambiguous capture leads to a request for better evidence.

### Speak and continue

Start by voice, interrupt, correct a detail, continue by text, and return later. The conversation and task state remain coherent. A Watch can eventually capture the same request and show a concise result, with a clear handoff if the phone is unavailable.

### Finish a bounded action

Ask for a reminder or a document transformation using permitted data. The app prepares the action, resolves missing details, obtains the appropriate commitment, performs it once, and shows a receipt. Canceling or losing the network must not falsely report completion or duplicate the action.

## 17. Release acceptance

The next release candidate must demonstrate these behaviors, not just contain buttons for them:

1. Fresh launch offers an available Apple model or a clear downloaded-model setup. Normal use requires no revision hashes.
2. Model import/download can be canceled and recovered; matching valid files are reused where accessible. Unsupported formats fail clearly.
3. A long synthetic conversation remains searchable after restart, with bounded model requests and retrieval of exact earlier evidence. Test at least 1,000 stored messages independently of the model's context size.
4. A changed memory is corrected across later answers, and deleted/excluded sources are not silently reintroduced by summaries or embeddings.
5. Documents and images can produce a cited, editable result, with revision history and working export.
6. A tool-rich task works with the tested local models and at least one optional remote route. Invalid, partial, duplicate, and unauthorized calls do not execute.
7. Local-only mode has a network-denial test that includes helper tasks, tools, memory processing, and retries.
8. Voice cancellation, audio interruptions, and transitions between speech and text preserve the user's work.
9. Background expiration, app termination, low storage, interrupted downloads, and unavailable models all have tested recovery paths.
10. A phone code runtime must pass termination, memory, filesystem, and network-isolation tests before being labeled a sandbox. Otherwise ship the verified deterministic tools and retain the broader runtime as an explicitly gated feature.
11. Physical-phone measurements cover the selected baseline and a larger candidate where feasible. No repeated crash, runaway heat behavior, or unresponsive Stop control is acceptable.
12. Updating over the existing installation preserves conversations, evidence, models, and user settings through a tested migration.

The basic Watch companion, Share extension, and background GPU mode each require a signing/capability check. Their architecture belongs in this design now; their inclusion in the same device package should be decided from those checks, rather than assumed from a successful simulator build.

Initial engineering targets, to validate and refine from device measurements:

| Measure | Draft target and test method |
| --- | --- |
| Stop control | Visible acknowledgement within 200 ms at the 95th percentile; separately measure how long the provider takes to stop work |
| Long-history opening | A 1,000-message saved conversation becomes usable within one second at the 95th percentile, with older rows loaded lazily |
| Model stability | Ten consecutive representative runs without an OS memory termination; include at least one image turn and a model switch |
| Context scaling | Record prefill time, first-token time, generation speed, and memory at several actual token counts; do not collapse these into one speed claim |
| Permission enforcement | Every automated denial test passes, including tool retries, background resumes, and indirect memory retrieval |
| Export and restore | A round trip preserves source IDs, artifact revisions, conversations, and permission choices; credentials and replaceable caches follow their separate policies |
| User value | The complete workflows above are easier to finish than in the current build, judged with real tasks and inspected outputs |

Provider quality should be evaluated with a small maintained task set: following constraints, using tools, grounded source answers, corrected memories, image evidence, and acknowledging missing information. Report performance by model and configuration. A model that writes attractive prose but repeatedly calls the wrong tool has not passed the assistant evaluation.

## 18. Sequence and unresolved decisions

First, settle the everyday conversation and model-library experience. Then design the exact context/memory lifecycle and tool/result contracts. Build document/research/artifact workflows on those foundations. Add voice and camera as first-class inputs into the same task system. Validate Apple entry points and Watch packaging against real provisioning capabilities. Only then assemble the substantial device release.

The main open questions are narrow:

- Can Locally AI export Jacob's complete Qwen model package, and what exact format/revision is it?
- Which Apple on-device variant and practical context configuration does this phone expose through the API?
- Can the documented ChatGPT authorization callback be made reliable in the native iPhone lifecycle?
- Which Watch, Share, and background GPU capabilities are available through the chosen signing route?
- Which constrained phone code runtime can meet real resource and isolation tests?

These are feasibility questions to resolve with focused evidence. They should not force Jacob to write a huge wishlist or repeatedly install cosmetic builds. The next design discussion should walk through one complete everyday task, then test the proposed screens, memory behavior, and permissions against that task.

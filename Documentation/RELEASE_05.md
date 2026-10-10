# 0.5 working scope — conversation reliability and interactive work

**Verified package ready for personal signing: 0.5.0 build 5**, source `c8855c12341ec73241333c285fb12db81d0cb109`. Jacob's phone screenshots established the original defects; those personal captures are not repository fixtures. Installation and live phone behavior still require Jacob's confirmation.

## Acceptance targets

- Preserve the reader's visible message/offset during ordinary scrolling, keyboard dismissal, streamed updates and tool expansion. Only deliberate sends/jump-to-latest or continued following at the bottom should advance the viewport.
- Keep public assistant prose at normal contrast. Render ordinary tool activity as compact gray disclosure rows without solid cards. Keep the accepted source footer.
- Put the effort control beside the microphone: circular 20/40/60/80 percent fill for Low through Extra High, black/white Max label for Max. Retain readable labels and touch targets.
- Send exactly the user's text; attachment-only messages have no invented prompt and no empty bubble. Put attachments above/outside the text bubble, make them openable, and put message actions below/outside the bubble.
- Editing a user message replaces that point and excludes subsequent messages, provider continuations and generated context from the next answer. Keep existing external files; do not pretend an edit reverses real-world actions.
- Give saved depth a useful inspection workflow with image coordinates, measurements tied to actual samples, quality/time labels and explicit geometric limits.
- Add reusable, validated native working surfaces for charts, comparisons, checklists and bounded interactive calculations. Interactions retain their object identity and result provenance; they are not hidden user-authored prompts or unrestricted scripts.

The app-generated ideas message is design input, not a mandate to implement every speculative feature. Extend existing memory/task records where useful; do not add passive life monitoring, a second Windows UI, or unsupported background execution.

## Implemented source

The conversation viewport now uses an owned UIScrollView and a bounded, eagerly laid-out message window. It retains the visible message and its offset as content or keyboard geometry changes, stops following when the user reads elsewhere, and provides explicit jump-to-latest. Keyboard dismissal uses native interactive behavior plus an accessible dismissal button. Native interaction tests passed; the phone retest remains necessary for real conversation sizes and keyboard behavior.

Assistant prose uses normal contrast. Tool receipts are compact gray disclosure rows; expanded details remain available. The accepted source footer remains. The thinking control is inline beside the microphone, with 20/40/60/80 percent circular fill and a black Max circle with white text. It retains the existing model-supported effort values and settings.

User text is preserved exactly, including attachment-only messages. App attachment IDs, times, types and selected points are separate metadata. Empty text parts are omitted from Responses image requests. Reattaching an image does not send duplicate copies from older messages. User actions sit below the text bubble, attachments sit above it, and images open a zoomable viewer.

Edit-and-send truncates the active transcript at the selected user message and replaces its answer. The same transaction removes later text from history search. Old provider output, generated context and working surfaces are excluded. Existing Library files and real-world actions are preserved. Automatically generated titles can be regenerated; old title text is withheld from model retrieval after an edit. Cancel restores the prior unsent draft and attachments.

Saved LiDAR captures support one-point depth and approximate calibrated two-point separation. Inspection filters missing/low-confidence samples, detects mixed-depth neighborhoods, maps display rotation back to native sensor coordinates, and labels capture time and limitations. Selected points can be attached to the conversation without inserting text. They are app interaction metadata, not fabricated user wording. Real-device accuracy is unmeasured; these are not object-size, fit, navigation or safety guarantees.

The reusable native surface protocol supports metrics, bar/line/area charts, tables, comparisons, checklists, timelines and adjustable arithmetic scenarios. Specs, data sizes, numeric ranges and formula depth are validated. No HTML, arbitrary scripts, network access or device actions run inside these widgets. Selections/parameters persist with revisions. The next model request receives bounded current-object state; read_surface retrieves details. Calculated values can be sourced directly from a successful JavaScript receipt instead of retyped by the model. Stale updates and removed-turn objects are rejected.

Saved memory distinguishes notes, preferences, projects, decisions and questions. It records user-maintained sources, confirmation and optional expiry. Tentative notes remain uncertain; superseded/expired notes remain inspectable but are excluded from new memory context. Existing notes migrate without invented confirmation. Memory discovery remains visible when the store is empty. The compact base prompt is retained; capability descriptions explain the actual app environment.

## Follow-on design, not capabilities claimed by this build

The inbox and routing proposal is useful: a future shared entry point should route Siri, Share Sheet and user-saved inputs to explicit conversations, and support saving without generating a reply. It should reuse the conversation store and preserve the source of each input.

Resumable task records should distinguish requested, drafted, reviewed, executed and verified outcomes, retain unresolved questions, and reconcile a possible side effect before repeating it. Existing transcripts and tool receipts are the foundation. A scheduling/notification system, Share extension, calendar readers, externally received message context and unattended execution have not been added in this batch. Their API/signing and permission routes require separate verification. Interactive selections do not grant those permissions.

## Primary references

- [Apple UIHostingController sizing](https://developer.apple.com/documentation/swiftui/uihostingcontroller/sizingoptions)
- [Apple ScrollGeometry](https://developer.apple.com/documentation/swiftui/scrollgeometry)
- [Apple Swift Charts interaction](https://developer.apple.com/videos/play/wwdc2023/10037/)
- [OpenAI conversation state](https://developers.openai.com/api/docs/guides/conversation-state)
- [OpenAI image inputs](https://developers.openai.com/api/docs/guides/images-vision)

## Verification

[Native run 38062830456](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38062830456), source `c8855c12341ec73241333c285fb12db81d0cb109`, passed **119 core tests, 15 native platform tests and 9 interface scenarios**, then built the Release iPhone and Watch targets. The final app source was validated in a full run. The shared suite also passed on Windows. Tests use synthetic local fixtures and do not make paid model requests.

The tests cover exact image-only input, selected-image metadata, edited transcript/title/output isolation, cancellation of an edit, legacy data decoding, rotated depth samples, widget data provenance and bounds, persistent selections, and memory lifecycle. Native UI coverage includes keyboard button and swipe dismissal, tool expansion/collapse, image preview, comparisons, and the actual 1+1 to 1+2 edit/regenerate flow. Full accessibility coverage, real LiDAR accuracy, external document-provider behavior and live-model quality are not established by these fixtures.

The archive was checked for its checksum, physical ARM64 iOS platform, Metal kernels, Files flags, dependency pins, phone-executable identity across the two archives and exclusion of the debug model fixture. [Native screenshots](Screenshots/0.5.0/README.md) and [validation receipt](ReleaseValidation05.json) retain the evidence.

## Spending

Recorded hosted-Mac usage totals 256 rounded minutes, estimated **USD 15.872 if fully billable**, within the authorized **USD 16 total** ceiling. Failed/cancelled execution is included; confirmed startup rejections with no runner consume zero runner minutes. This is not an account invoice. The October 10 billing snapshot showed USD 12.00 gross compute fully discounted and zero net billed compute, but reporting may lag later jobs. Preserve the conservative ceiling; taxes and future storage are separate. Full jobs remain capped at 20 minutes.

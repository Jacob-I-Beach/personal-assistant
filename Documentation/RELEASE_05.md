# 0.5 working scope — conversation reliability and interactive work

Status: source implementation is ready for native validation as 0.5.0 build 5. Jacob's four screenshots and phone report identify the changes below. Personal screenshots are not repository fixtures. Jacob explicitly increased the total hosted-Mac ceiling to USD 16 on 2026-10-10. The estimate before 0.5 validation is USD 11.718 if fully billable; full jobs remain capped at 20 minutes. Native compilation, screenshot inspection and phone verification are still pending.

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

The conversation viewport now uses an owned UIScrollView and a bounded, eagerly laid-out message window. It retains the visible message and its offset as content or keyboard geometry changes, stops following when the user reads elsewhere, and provides explicit jump-to-latest. Keyboard dismissal uses native interactive behavior plus an accessible dismissal button. This is an implementation claim; the actual iOS behavior must pass the native tests and Jacob's phone retest.

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

## Verification required

Regression tests must cover empty-text image/file inputs, replacement-context isolation including history search, edit cancellation, stable scrolling/keyboard/disclosure positions, effort selection and compact composer, attachment previews, depth-coordinate rotation/sample validity, surface validation and interaction state. Windows core tests and syntax parsing are followed by a separately budgeted native compile/UI run. Phone behavior remains unconfirmed until Jacob retests it.

All 119 local tests passed on Windows, including the localhost HTTP fixture, exact image-only inputs, edited history/title/output isolation, legacy decoding, depth coordinates, widget data provenance, formula bounds, persistence and memory lifecycle. Swift syntax parsing also passed. [LocalValidation05.json](LocalValidation05.json) records the boundary. Native coverage is prepared for 15 platform tests and 9 UI scenarios. Only an actual successful Xcode run establishes native compilation and test results; this source batch has no new installable IPA yet.

Native run 38056583781 compiled the application and passed 119 Mac core tests, all 15 platform tests and five of nine UI scenarios, including the actual image/surface/edit-regenerate flow. Three UI failures showed visible content missing from the hosting controller's accessibility tree; the fourth showed that native scroll dismissal did not resign the composer in the enclosing SwiftUI root. The repair passes only public presentation values into the child host, uses explicit parent navigation, and hands downward keyboard dismissal back to the composer. Full revalidation is required. The recorded compute estimate after that 14-minute job is USD 12.586 of the authorized USD 16 total.

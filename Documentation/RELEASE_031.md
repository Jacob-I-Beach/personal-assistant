# 0.3.1 build 4 — response presentation

Jacob's live 0.3 GPT 6.1 Sol Jupiter test returned a good sourced answer and a successful JavaScript result. Five user-supplied screenshots establish the presentation problems below. Those personal screenshots are not checked into this repository.

## Changes

- Preserve public response item/content boundaries and provider commentary/final-answer phase during streaming and on disk. Progress paragraphs stay separate, with hosted web activity in its actual position.
- Restore this presentation for existing 0.3 messages when saved provider items match their original text. Preserve original transcripts and opaque provider continuations; do not show reasoning items or encrypted content.
- Show one copy/share/read-aloud action group after a completed assistant turn. Intermediate updates, tool requests, running turns and failed/partial responses do not receive final-answer actions. Older finished turns remain usable while a new response streams.
- Persist actual reported web searches, page reads and in-page searches, including returned queries and safe source links. A citation alone never invents a search receipt. Unconfirmed/interrupted activity cannot remain an endless spinner.
- Present JavaScript results as readable named values. Code and exact JSON remain under separate disclosures; display rounding never changes stored results.
- Use pinned Textual 0.5.0 and SwiftUIMath 0.1.0 for native structured text and equations. Adapt model-produced backslash math delimiters while preserving code spans/fences. Keep remote image/emoji loading disabled and explicit HTTP/HTTPS link handling.
- Include the new dependency licenses in acknowledgments. Existing model, signing, file permissions and offline execution policies remain in force.

## Validation

85 shared-core tests pass on Windows, including actual localhost HTTP streaming. Added regression cases cover the screenshot sequence, Unicode/citation offsets, exact provider-phase replay, legacy transcript loading, missing/changed terminal text rejecting tool execution, one final action group per turn, stopped web activity, readable numeric formatting and math delimiter adaptation.

A dependency-resolution fixture confirms compatibility with the project's SwiftSyntax constraint. Swift syntax parsing passes. Neither substitutes for Xcode compilation.

Native validation pending: two math parser tests, a synthetic iPhone UI walkthrough of progress/web/calculation/math/final actions, the existing four UI tests and eight platform tests, and physical iPhone/Watch Release builds. A native screenshot review and integrity-checked iPhone-only package are required before delivery.

The current installed version remains 0.3.0 build 3. The image/depth request still needs a physical-device retest. The prior $10 total hosted-Mac ceiling applies; before this batch the ledger totals an estimated $8.618 if all recorded minutes are billable.

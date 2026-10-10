# Personal Assistant 0.3 — implementation and validation

Status: source implementation ready for native validation. Installed phone version remains 0.2.0 build 2. This is a coherent release batch, not an installable update yet.

## Implemented in the working source

- ChatGPT-primary onboarding, with the selected model preserved and no silent provider fallback.
- Fresh conversation on cold launch; saved chats and drafts are resumed from a slide-out sidebar. Authentication, file pickers and normal foreground transitions retain the active chat.
- Topic folders with optional instructions; rename, move, archive, restore and confirmed deletion. Additive database migrations preserve existing messages and artifacts.
- Files, photos, camera and Library in the attachment menu. Per-response playback plus an optional voice setting replace the read-aloud attachment toggle.
- App-owned file originals, Library search, Quick Look preview, sharing, and per-file workspace access. Text, PDF, DOCX, PPTX and XLSX extraction is bounded and explicitly describes what was omitted. Office text uses pinned ZIPFoundation; no macros or document scripts execute.
- Recent supported file originals can be passed to OpenAI Responses alongside extracted-text tools. Up to two originals and 25 MB total are included per request; other sources remain readable through bounded text retrieval. Input support depends on the selected model.
- A real paginated PDF writer on the phone, plus existing text/Markdown/CSV/JSON/code/HTML/SVG creation. Text tools reject binary extensions instead of producing mislabeled files.
- Optional assistant search across permitted app chats and Library files. Connected search excludes archived, local-only and Health chats. This does not import history from the separate ChatGPT app.
- Honest public work plans, compact tool receipts, source links and visible persisted failure messages. Provider-internal reasoning is not displayed.
- ChatGPT web-search request support where account/model policy allows it; annotated sources become clickable. The JavaScript runtime remains isolated and offline.
- Runtime device resources; one foreground location after explicit review; user-reviewed calendar creation and message composition; reviewed Maps and Phone handoff. These do not grant message-history, call-history, arbitrary settings or cross-app control.
- Ten pinned local model packages: existing Qwen 3.5 2B/4B/9B; IBM Granite 3.3 2B and Granite 4.0 H Tiny; SmolLM3 3B; Liquid LFM2 1.2B and LFM2 8B A1B; Gemma 4 E2B/E4B. Memory estimates are heuristics, speed is unmeasured. Factory loading preserves upstream tool/EOS configuration and distinguishes text and vision architectures.
- Compact tool discovery for small-context backends; the full tool set is available directly to larger-context backends.
- Existing Shortcuts entry point retained. Watch and Health code remain subject to the installation/signing limitations below.

## Observed bugs addressed

The installed Apple model's sum/file failure came from a rejected plain-array JavaScript return followed by a fabricated CSV. Plain JSON returns now work; success/failure receipts are explicit; a failed or unfinished calculation blocks follow-up artifact/PDF creation until successfully retried. The exact three inputs compute 60.5 in regression tests.

The ChatGPT blank-response symptom also occurred for a text-only Jupiter question, so it is broader than image input. A confirmed parser defect discarded completed streamed tool calls when the terminal response had an empty output list. The reader now retains them, handles final-only/refusal text, and rejects genuinely empty completion. These are tested corrections, not yet confirmation of the actual phone symptom's resolution.

## Validation completed on Windows

- 75 shared-core tests passed, including real localhost HTTP streaming/tool loops, persistence/migration, file-sharing boundaries, original-byte preservation, compact tool discovery, public plan validation, source links, and original-file request encoding.
- 34 native app/test Swift sources passed syntax parsing only. This does not typecheck Apple frameworks or certify UI behavior.
- Info.plist parses; all 10 catalog totals and weight hashes are internally consistent. Seven new model revisions and architecture metadata were read from Hugging Face; no weights were downloaded to the PC.
- Native platform tests added for DOCX/XLSX extraction, XML entity rejection, multipage PDF creation and device identity minimization. UI coverage adds fresh launch, attachment actions, folders and sidebar. These tests await Xcode.

## Pending release gates

1. Approved hosted-Mac validation and any necessary repairs: core tests, native typecheck/build, platform tests, UI tests and actual simulator screenshots.
2. Inspect native screenshots for light/dark mode, larger text, sidebar, Library and attachments; fix layout issues found.
3. Produce and verify a versioned iPhone-only unsigned IPA while retaining the full compiled Watch archive.
4. Jacob installs via iLoader; all GUI, Apple authentication and phone prompts remain user-operated.
5. Phone checks: GPT 6.1 Sol Jupiter/tool request and image/depth request; calculation-to-CSV; file reading/PDF creation; web search/source links; action cancellation/save/send; local model load/tool behavior and measured resources.
6. Watch companion and HealthKit are still unavailable in the current official iLoader iPhone-only signing route. Private Cloud Compute requires the app's actual approved entitlement; consumer availability alone is not assumed to establish it.
7. Full browser automation, Python, an always-running background agent, cloud execution workspace and arbitrary iOS device control are not implemented. Do not label them complete.

## Build spending boundary

The nine completed hosted-Mac jobs total 80 rounded minutes, estimated at $4.96 if fully billable at $0.062/minute. Actual account credits/invoice have not been read. Jacob explicitly raised the total hosted-Mac validation ceiling to $10 in chat after reviewing this batch. The workflow has a 20-minute per-job timeout (about $1.24 per fully billed run at the recorded rate). Keep total estimated compute within $10.

## Sources checked for this batch

- [Sign in with ChatGPT inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference) and [preview limits](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).
- [OpenAI file inputs](https://developers.openai.com/api/docs/guides/file-inputs) and [web search](https://developers.openai.com/api/docs/guides/tools-web-search).
- [Apple one-shot location](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation()) and [Calendar/EventKitUI access](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui).
- [MLX Swift LM 3.32.3](https://github.com/ml-explore/mlx-swift-lm/tree/3.32.3); package revisions and metadata in ModelCatalogAudit.json.
- [ZIPFoundation 0.9.20](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.20).

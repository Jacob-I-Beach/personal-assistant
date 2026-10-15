# 1.3.1 build 25 — reply allowance after compaction

Prepared in response to the installed 1.3.0 report: GPT-6.1-Sol with the largest 855,616-token choice showed only 16,384 tokens for a reply, despite the 30% reserve row. Native verification and packaging are in progress.

## Added

- A regression using the exact 872,000 connection window and 855,616 selection, plus real request serialization checks for normal replies, compaction and the ChatGPT-plan route.
- An input allowance specifically for checkpoint generation, which respects the published maximum input when a larger working allowance is selected.
- Two worker regressions: each completes 20 operations across at least three native or portable compactions on the same task, retaining exact receipts without repeating completed effects. These use synthetic model responses and do not establish live inference quality.

## Changed

- Reply allowance now uses active input after the 30% headroom calculation. The old formula subtracted all 855,616 tokens from 872,000 even though normal request assembly only uses 598,931 active input tokens. It displayed 16,384 instead of the 128,000 normal reply/reasoning allowance.
- Compaction retains its own calculation because it may use more source input. At the reported selection, the separate compaction request has 855,616 input tokens and 16,384 output tokens; the normal request has 598,931 active input and up to 128,000 output. Those are separate passes, not additive reservations.
- Settings now say "Reply and reasoning: Up to ..." and explain that the reserve is headroom rather than occupied conversation. The connection enforces its actual limits, and token accounting remains an estimate until the provider/native tokenizer measures it.
- The reply figure is explicitly per model response, not a whole-task limit. PC work can span multiple model responses and compactions. Existing cancellation/authority checks, provider limits and genuine pending dependencies still apply.
- API-key/compatible requests choose the output allowance for the request type. ChatGPT-plan requests continue to omit the unsupported `max_output_tokens` field, including the requests forwarded through the PC. The incorrect 16K display was not an app-imposed 16K cap on the user's ChatGPT connection.

## Removed

- The pre-compaction subtraction from the normal reply calculation. No selected history, saved work, account, pairing or PC task state is removed or reset.

## Still pending

- Native build/interaction verification, signed-input package checks and user-operated in-place phone installation.
- No live model inference is used for this repair. Existing 1.3.0 physical acceptance and deferred memory/Health/notification provisioning remain separate.

The PC companion remains 1.3.0 release r2; this correction does not require a service restart or account reconnection. The source preserves the 855,616 selection and 30% compaction policy.

## Source and checks

[Official GPT-6.1-Sol model documentation](https://developers.openai.com/api/docs/models/gpt-6.1-sol), fetched October 15, 2026, lists a 1,050,000 context window, 922,000 maximum input and 128,000 maximum output. The narrower advertised connection window remains authoritative in the app. These published model limits are not a guarantee of identical limits for every ChatGPT account.

# End-to-end audit: 1.1.4

Jacob requested a root-cause review after repeated releases missed fresh AFM requests and ChatGPT model-list failures. This audit follows production request assembly, account/catalog state, native and computer tool loops, durable recovery, model choice, rendering, downloads and release validation. It does not claim every capability has been exercised on a physical iPhone.

## Confirmed defects and repairs

| Boundary | Evidence | Repair and verification |
| --- | --- | --- |
| AFM before inference | A new production-engine test with the actual 10,000-byte on-device ceiling fails on “Hello” with the exact reported tool-fit error. The old UI backend used the default 32,768-byte ceiling. | Shared Apple context policy; compact task/evidence/review instructions and app orientation; real budget in UI fixtures; whole production request tested. Full connected-model instructions retained. |
| Final request accounting | Turn instructions and attachment/context notices were appended after history selection. The PC separately counted input but omitted instructions/tools and counted UTF-16 characters as bytes. | Account for all components before selection, validate the assembled request, count UTF-8 on the PC, and reject unreducible input without silently shortening the user's message. Native Apple token counting adds an actual runtime preflight. |
| Native tools after the first call | AppleToolGate returned unbounded receipts into a small SDK session. Large capability listings could exhaust it immediately. | Compact capability summary, bounded receipt pages, exact read_tool_result retrieval, full saved receipts, and a new session after a tool-driven context overflow. Regression verifies an artifact is created only once and the answer completes. |
| Native session reconstruction | A saved last tool output was removed from its transcript and passed back as a fresh user prompt. | Preserve its role in the transcript; use a continuation prompt. No invented user message is persisted. |
| Tool discovery | A query with zero matching words returned the first two phone tools or three computer tools. | Require a positive match and use deterministic ordering. Exact schemas remain discoverable; all authorized tools remain callable. |
| GPT catalog transport | A fresh authenticated, non-inference GET to the documented /v1/models endpoint still returned HTTP 520 with an unparseable upstream response. The saved session and sharing remained present. | Do not clear credentials or assert a global outage. Preserve the real failure separately from sign-in and PC reachability. Restored upstream model discovery is not claimed. |
| Model choice persistence | No disk catalog on either side. Direct-account errors cleared all choices; successful direct refresh silently replaced a missing selected model. Refresh errors were outside the picker. | Account-scoped saved catalogs on phone and encrypted PC storage, explicit refreshing/ready/stale/unavailable states, visible refresh/recovery controls, last chosen model with unconfirmed availability, account-switch and stale-response guards. Never infer account entitlements from a guessed catalog. |
| Saved GPT work under AFM | The local-selection guard silently ignored a manual “Sync latest reply” tap. | Card explicitly opens model choice for the older GPT task and states that new messages use the current model. Sending a new local message stays local. |
| UI and evidence coherence | “Connected” implied availability while the model route failed; the test runtime differed from production. Historical docs still described an active bridge. | Separate signed-in and model-service states in both UIs; align the local fixture with production; mark historical bridge instructions. Visual review also moved download controls below model choices and corrected the background setting to describe iPhone time independently of computer-owned tasks. Native UI and platform coverage are recorded in the release ledger. |
| Optional-service coupling | Both account/capability and control-center status requests awaited fresh Docker subprocesses, each with a 15-second timeout. An unavailable optional Python service could delay otherwise healthy account/job access and repeated status polling started redundant probes. | A separate, bounded, cached computation-health probe returns checking/ready/unavailable without gating account, models, saved work or control-center access. Slow/error probes are tested independently. |

## Adjacent contracts checked

- Send acceptance, server-owned work, disconnect/replay, typed tool receipts, source ordering and file publication: existing companion/core regression suite rerun with these changes.
- Stop, action idempotency, cancelled/unknown outcomes, permissions, questions, saved files and account ownership: regression suite retains those checks. No inference fallback or automatic credential reset added.
- Local model download: native pinned-byte download/reuse platform check included. Real multi-gigabyte download and sustained memory remain phone tests.
- Native schema conversion, review dismissal, edit cancellation, response row sizing and math: included in native audit suite.
- Questions, live research re-entry and working surfaces: included as nearby UI regression flows.

## Deliberate limits

Health and task notifications/Live Activities remain deferred. No bridge is reconnected. No local model runs on the PC. No new paid service, API key, live model call, account sign-in or phone installation is part of this verification. Apple's physical model quality, its actual token limits on this device, and sustained local memory require physical acceptance. A verified cached list cannot establish current inference availability.

## Validation policy correction

A scripted transport can replace inference for tests; it must not replace the production context policy, request assembly, tool schemas, persistence, selection or recovery logic. Passing a canned answer through the UI alone is insufficient evidence that a real backend can accept a request. The reproduced pre-patch failures and post-patch evidence are retained outside the repository in the local build/audit logs; release artifacts cite the exact source revision.

## Verified references

The supported ChatGPT-plan route is described in [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference). [Codex app-server with this authorization](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server) uses the same public Responses route; a bundled model list is not an account entitlement check. Apple documents whole-session accounting and its tokenizer in [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window). The production app retains a conservative byte budget and checks native tokens at runtime.

The real Docker integration was also rerun: assistant.publish, saved-state continuation, CSV input, checked spreadsheet formulas, PDF creation/page inspection and sandbox boundaries passed. The rendered PDF was visually inspected.

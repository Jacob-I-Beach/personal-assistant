# Companion protocol and execution contract

Version 1.1 contract. Physical phone and provisioned-push acceptance remain separate from synthetic protocol evidence.

## Ownership

The computer durably accepts each enabled connected task at Send. `start_when_ready` starts it after the declared input IDs exist, independently of another phone start RPC. Losing a phone subscription only disconnects that subscriber. Explicit Stop cancels the job. Enqueue uses a device-scoped idempotency key and content hash; a duplicate key with changed content is a conflict. Progress events have durable increasing sequence numbers so reconnects request only subsequent events.

The computer uses its own user-authorized ChatGPT plan profile. It keeps the model stream alive and executes supported file/computation tools. It never receives the phone's OAuth or Apple credentials. Phone-only tools become persistent device requests; their outcomes are deduplicated before work continues. Unknown consequential outcomes are inspected rather than repeated.

## Transport and pairing

- Setup/account controls are loopback-only, with origin/CSRF checks.
- Phone endpoints use TLS with explicit certificate verification and a revocable paired-device credential. Pairing codes are short-lived and single-use.
- Job/data endpoints check ownership on every request. Inputs are explicit snapshots or granted file references, not arbitrary host paths.
- With Computer enabled, connected tasks use one server owner from Send. Disabling that connection explicitly selects the ordinary phone path; there is no automatic background handover.
- A private connection is needed away from the home network. Tailscale is a candidate; do not publish an unauthenticated endpoint or silently change VPN/account permissions.

## Model and tool loop

Use the existing Responses input format and the actual permitted tool catalog. ChatGPT plan inference sets `store:false`, `stream:true` and omits unsupported `background` and `max_output_tokens` fields. Only complete validated calls may execute. Retain opaque reasoning/output continuation for the same account/model. Model retries cannot repeat an uncertain external action.

The host should execute discovery and its own file/computation tools. Other eligible app calls are durable phone requests, including Health, contacts, location, questions, messages and planning review. The phone retains execution-time permission/version checks. Results report the actual execution location.

## State and files

`JobStore` encrypts task payloads, event bodies, operation arguments/results and artifact bytes using authenticated encryption under a Windows-protected key. Artifact revisions retain a stable ID and expected-version checks. Credentials use the upstream SDK's OS-backed encryption interface. No credentials appear in a browser, phone payload, generated-code environment or logs.

Generated code runs in a separate bounded environment with only selected inputs. The planned Docker route uses no task network, no Docker socket, a read-only root, reduced privileges, bounded CPU/memory/process count, and bounded temporary/output storage. Do not bind unrestricted host folders. Return only declared results and permitted output files. Install parsing, scientific and document packages during controlled environment setup, not from model-generated code.

## Phone integration

Expose a Computer connection and pair flow, preserve model choices, and provide honest running/waiting-for-phone/needs-review/completed/failed states. Reattach to the same job after foreground return or app restart. Phone suspension must not cancel computer work or create a false processing-failed activity. Use a real activity presentation with timestamps and supported background delivery; do not fabricate progress or promise APNs delivery without a provisioned service.

## Verification

Use synthetic provider streams and phone-tool responses to prove disconnected work completion, replay/cancellation behavior, ownership checks and version conflicts. Run actual bounded computation and reopen/render its outputs. SDK account connection and a real user-selected model request remain user-operated checks, not paid automated tests.

## Host tools and notifications

Scoped file access uses canonical paths and task-specific grants. Host commands are reviewed with exact command/cwd before execution; awaiting-review and started are distinct persisted states. Uncertain started operations are never automatically repeated. Browser/desktop actions bind fresh observations and are not equivalent to an external delivery receipt. APNs configuration and tokens are encrypted; task state drives pushes and notification deduplication. The ordinary personal-signing app remains push-disabled until a matching developer-provisioned build is installed.

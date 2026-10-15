# 1.3.0 build 24 — task ownership and continuation

The Windows companion 1.3.0 release r2 is installed. The iPhone 1.3.0 build 24 package is compiled, structurally verified and ready for in-place personal signing. It has not been installed on Jacob's phone by the agent. No live model inference was used for validation.

## Added

- PC-owned tasks continue through working sessions without the former 30-round/40-action stop. Transient model transport failures retry with backoff; cancellation and account/device authority are rechecked.
- Pending questions, phone actions and exact computer reviews are durable dependencies. Independent tools can proceed; a late answer resumes the same job. The phone services native requests independently from its transcript subscription. Later messages do not orphan older computer questions; completed older turns merge atomically without replacing newer messages.
- A 30% compaction reserve across context choices, source-linked checkpoints for phone models, and PC context archives with bounded retrieval and image inspection. The PC prefers native OpenAI compaction when the existing connection accepts it, preserving the canonical output unchanged, and falls back to a factual checkpoint or exact saved evidence. Source edits invalidate phone checkpoints. The full conversation and operation receipts are retained.
- Five discoverable task playbooks for research, documents/data, computer work, phone/planning and code/long work. Skills organize existing capabilities; they do not confer permissions.
- Scoped computer file search and version-checked text patches. Desktop observations include monitor orientation, coordinate conversion and display-arrangement identity.
- Python state handles now retain up to 24 MiB of JSON outside model context. A real isolated execution saved and reopened a 2 MiB state object; its model-facing receipt remained under 4 KiB. This addresses three recorded failures in the reported code-audit task that hit the former 1 MiB state limit. That task also contained generated-code failures; the larger state allowance does not establish that every code failure is resolved.

## Changed

- New requests select the ready paired PC account or the separately authorized phone ChatGPT account. An uncertain submission or a lost observer connection never creates a fallback copy. An accepted task keeps its owner.
- The computer toggle governs new work. Mobile, local and saved computer recovery remain distinct; PC snapshots and recovery cards no longer say a phone-owned response stopped or offer its Continue reply action.
- Native questions can be staged without a modal blocking the worker. Answers and supplied image pixels retain their task provenance. Pending operations have pending presentation, not a completed checkmark.
- Compaction accounts for instructions, tool definitions, results and available provider usage. Byte estimates are conservative working limits, not exact token measurements. Apple/MLX additionally enforce their native limits.
- Incomplete output-limit responses preserve public text for continuation, without authorizing incomplete tool calls. Repeated failures ask a concrete recovery question instead of silently looping.
- The effective connection controls the account identity and model catalog shown on the phone. A configured but unavailable PC does not lend its email or model cache to the mobile connection. First mobile authorization preserves the existing PC model preferences.
- PC-native reviews remain internal protocol operations; they are not exposed as tools the model can invoke without an underlying action. Resolving or cancelling an old review advances the native review queue without cancelling unrelated current work.
- Older phone tool catalogs receive the current PC tool contract at execution. Generated state/artifacts no longer consume the input-upload count; file listings avoid loading stored binary blobs. Long Python diagnostics preserve the final exception. State-derived results retain protected-source flags.

## Removed

- Fixed interactive PC session limits as user-facing restart requirements.
- The unused automatic mobile-to-PC handoff path and the blocking PC phone-wait loop.
- Mobile-style Continue reply and stopped-response labels for PC-owned tasks. Those tasks reconnect to their saved job; genuine cancellation, missing authorization and pending input retain their own states.

## Still pending

- User-operated phone signing/install and physical acceptance; no live model inference is part of automated verification.
- A separate mobile ChatGPT sign-in if none is saved on the phone. Account scopes and provider limits still apply.
- Previously deferred increased-memory profile/physical 64K verification, Apple Developer provisioning for Health/APNs, and physical background/network acceptance. Notifications/PushWard/Health remain disabled.
- Native compaction through this particular ChatGPT-plan account has not been live-tested. Its protocol and fallback paths are tested. GPU program availability and interactive desktop actions still depend on the actual installed software and unlocked Windows session.

## Operating contract

| Situation | New request | Existing accepted work |
| --- | --- | --- |
| Computer enabled, reachable, paired and account sharing ready | Uses the PC's authorized GPT connection | Continues on the PC after the phone viewer closes; synchronizes the same job, events and files on return |
| Computer disabled or unavailable | Uses the separately authorized mobile GPT connection; prompts to connect it if absent | PC work keeps its original owner; no duplicate mobile submission |
| Local Apple or downloaded model selected | Runs on the iPhone | Does not resume an old GPT task under the local model |
| Question or reviewed action pending | Independent PC work may proceed | The question/action remains bound to its original task and exact source; a later answer resumes that job |
| User stops, permission is removed, or an external action's outcome is unknown | Cancellation/authority is checked at execution | Cancelled work cannot revive; an uncertain external effect is not automatically repeated |

The computer must be awake and online for PC work. Chrome may be closed; the service starts at Windows sign-in. The switch does not migrate an already accepted task or cancel it. Turn the switch back on to automatically synchronize saved PC work. A network failure before submission is different from losing the acknowledgement after a possible acceptance: only the former permits a new mobile route.

## Context policy

Every selected working allowance keeps 30% for compaction and continuation. For the connected 1,000,000-token choice, active input is 700,000 and the reserve is 300,000; reply capacity is tracked separately within the provider's advertised total limit. Local choices also subtract reply/runtime overhead: a selected 65,536-token window yields 42,803 active input, 19,661 reserved, 2,048 reply and 1,024 runtime overhead. The UI displays these parts.

The reserve is processing headroom, not a guarantee that a summary retains every fact. Full chat/source history and exact receipts remain stored; checkpoints contain current objectives, decisions, progress, dependencies and source handles. Native opaque context is preserved unchanged when available; otherwise the portable checkpoint/archive path applies. Edits invalidate dependent phone checkpoints. Large state, files and old tool outputs are reopened by bounded references rather than repeatedly injected in full.

## Verification

- 277 Windows core and 277 Mac core checks passed. 27 focused native platform checks (including TLS) and eight UI scenarios passed. The actual screenshots were visually inspected for the changed flows; these use synthetic data, not phone captures.
- 91 companion regression checks, seven updater checks, four real Docker/Edge integration checks and the production PC control-center browser flow passed. The Python image is `personal-assistant-compute:1.3`.
- Continuity checks ran 65 synthetic tool rounds, a real service restart after a simulated 90-minute absence, 12,000 streamed fragments, a late answer with newer messages present, partial model output, context overflow/compaction, and cancellation after an external effect started. These validate the application mechanics, not real-model answer quality.
- Native source: `dd856c5d67fae494f58e45f4b7d20683f2682712`, run `38701690741`. Core and both simulator jobs passed. Device compilation, package validation and artifact upload succeeded; the device job exceeded its 20-minute allowance during cleanup, so the overall run is accurately recorded as cancelled. Downloaded package hashes and structure were separately rechecked. Earlier successful candidates are retained as evidence, not substituted for this source.
- Installed PC source: `a93e2b8`, release r2. A consistent encrypted backup was taken; account identity, one pairing, 28 task IDs, TLS certificate, data location and actual Windows sign-in startup were preserved. Certificate-pinned Tailscale HTTPS returned 200; authenticated model discovery returned eight models including GPT-6.1-Sol. No model-generation prompt or personal action was sent.

Machine-readable evidence is in `ReleaseValidation130.json` and `DeviceValidation130.json`. The install folder includes Standard/Memory IPAs, hash receipts, installation instructions and actual synthetic native previews. The Memory IPA requests an entitlement; only the matching Apple profile and actual iOS grant determine its effect.

## Physical acceptance after installation

1. Confirm About shows 1.3.0 build 24 and existing chats/files/downloads remain.
2. With computer mode on, send a multi-step request, leave/lock the app and return to the same result, tool steps and files. Repeat across cellular/Tailscale.
3. Let a task ask a question while doing independent work. Reply later and verify it resumes the original task without overwriting a newer message.
4. Turn computer mode off; connect mobile ChatGPT only if necessary. Verify a new request uses that route and mobile interrupted-reply recovery. Select Apple and Qwen separately to verify local isolation.
5. Only after the memory profile grant is verified, test sustained 64K local inference and record real peak memory/speed. A simulator memory fixture is not hardware evidence.

## Design reference

OpenAI recommends compaction as retained task state, preserving source continuity across long work: [API deployment checklist](https://developers.openai.com/api/docs/guides/deployment-checklist#leverage-compaction). The candidate uses the existing authorized account for native compaction when supported, and a portable checkpoint fallback otherwise. Endpoint acceptance by this particular ChatGPT-plan account is not established by synthetic protocol tests. It is not a claim about Codex's hidden configuration.

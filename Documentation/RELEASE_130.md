# 1.3.0 build 24 — task ownership and continuation

Candidate under verification. This file is not an installation or live-model acceptance receipt.

## Added

- PC-owned tasks continue through working sessions without the former 30-round/40-action stop. Transient model transport failures retry with backoff; cancellation and account/device authority are rechecked.
- Pending questions, phone actions and exact computer reviews are durable dependencies. Independent tools can proceed; a late answer resumes the same job. The phone services native requests independently from its transcript subscription.
- A 30% compaction reserve across context choices, source-linked checkpoints for phone models, and PC context archives with bounded retrieval and image inspection. Source edits invalidate phone checkpoints. The full conversation and operation receipts are retained.
- Five discoverable task playbooks for research, documents/data, computer work, phone/planning and code/long work. Skills organize existing capabilities; they do not confer permissions.
- Scoped computer file search and version-checked text patches. Desktop observations include monitor orientation, coordinate conversion and display-arrangement identity.

## Changed

- New requests select the ready paired PC account or the separately authorized phone ChatGPT account. An uncertain submission or a lost observer connection never creates a fallback copy. An accepted task keeps its owner.
- The computer toggle governs new work. Mobile, local and saved computer recovery remain distinct; PC snapshots and recovery cards no longer say a phone-owned response stopped or offer its Continue reply action.
- Native questions can be staged without a modal blocking the worker. Answers and supplied image pixels retain their task provenance. Pending operations have pending presentation, not a completed checkmark.
- Compaction accounts for instructions, tool definitions, results and available provider usage. Byte estimates are conservative working limits, not exact token measurements. Apple/MLX additionally enforce their native limits.
- Incomplete output-limit responses preserve public text for continuation, without authorizing incomplete tool calls. Repeated failures ask a concrete recovery question instead of silently looping.

## Removed

- Fixed interactive PC session limits as user-facing restart requirements.
- The unused automatic mobile-to-PC handoff path and the blocking PC phone-wait loop.

## Still pending

- Native build/interaction evidence, final packaging and installed-PC verification are in progress.
- User-operated phone signing/install and physical acceptance; no live model inference is part of automated verification.
- A separate mobile ChatGPT sign-in if none is saved on the phone. Account scopes and provider limits still apply.
- Previously deferred increased-memory profile/physical 64K verification, Apple Developer provisioning for Health/APNs, and physical background/network acceptance. Notifications/PushWard/Health remain disabled.

## Design reference

OpenAI recommends compaction as retained task state, preserving source continuity across long work: [API deployment checklist](https://developers.openai.com/api/docs/guides/deployment-checklist#leverage-compaction). The current candidate's portable checkpoint path uses the existing authorized connection and does not assume that the ChatGPT-plan connection supports a separate compact endpoint. It is not a claim about Codex's hidden configuration.

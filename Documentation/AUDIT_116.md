# Full supplied-audit pass — 1.1.6

The supplied Code Audit and issue register target `54f2c3c7cbca8be7bf12677eb5c78fd180fd225e`. Its newly supplied extracted directory matches the earlier ZIP. All nine baseline source blobs verified, and all eleven supplied Node failure cases reproduced on Windows/Node 24+. The separate original Swift validator reproduction accepted 1e30 and terminated its deliberately isolated conversion child. Those old-behavior reproductions are evidence of the defects, not acceptance tests.

The current production paths were reviewed for all 18 findings, with their positive regression tests run against the current checkout. No supplied source fixtures were copied into production. Tests use synthetic accounts, files, tools and model providers. The real Edge check uses a generated local DOM, not a user's browser account.

| ID | Current disposition and evidence |
| --- | --- |
| PA-001 | Fixed in 1.1.5; checked exact-integer domain and actual project dispatch are covered by AuditRegressionTests. The old Swift child trap was reproduced separately. |
| PA-002 | Fixed in 1.1.5; scheduled discovery and dispatch enforce the allowlist after nested use_tool resolution. Scheduler/runner test denies host effects and permits isolated Python. |
| PA-003 | Fixed in 1.1.5; current integration revokes through the real setup endpoint with four running synthetic jobs, an older queued job and a live tool-only child. Restart does not admit revoked work; a real late receipt survives. Component tests cover linked handoff cancellation and ownership rechecks. |
| PA-004 | Work metadata fixed in 1.1.5. This pass additionally reproduced and repaired missing protection flags on a project-update receipt referencing protected outputs. Local/private/Health/legacy canaries, positive public access and persistence are covered. |
| PA-005 | Fixed in 1.1.5; optional receipt fields round-trip through the real decoder. Additional engine-level commit test accepts a matching answer/workspace and rejects a foreign-turn answer without committing its workspace authority. |
| PA-006 | Fixed in 1.1.5; native callbacks stop before the 25th effect across rollovers. Added 60 concurrent admission attempts: exactly 24 admitted; repeated identities rejected. |
| PA-007 | Fixed in 1.1.5; recovery reconstructs 31 journal receipts. Existing WorkRecoveryTests independently preserve unknown outcomes and avoid replaying effects or inventing a user prompt. |
| PA-008 | Fixed in 1.1.5; publication failure leaves a replayable checkpoint and exactly one real effect. Handoff batch and host-review receipt transactions are checked separately. |
| PA-009 | Fixed in 1.1.5; terminal event failure rolls back status/cursor. Added actual file-backed database reopen before retry and after successful completion. |
| PA-010 | Fixed in 1.1.5; model-update and user-interaction triggers fail after the history insertion boundary; both roll back. Added reopen/retry and live-history preservation checks. |
| PA-011 | Fixed in 1.1.5 with exclusion/rebuild semantics, not external-file rollback. Edited-away artifact/surface/project revisions cannot silently reenter the branch, while actual saved outputs remain. Independent external writes are deliberately retained. |
| PA-012 | Fixed in 1.1.5; deletion removes current/history records. Added startup reconciliation of an emulated orphan and persistence of an unrelated chat's revised artifact. This is logical deletion, not forensic erasure of backups/WAL. |
| PA-013 | Fixed in 1.1.5; exact owner/key lookup, aggregate counts and unique request-key index replace display-page queries. Tests exceed 100 records and retain duplicate legacy history while disabling duplicate scheduling. |
| PA-014 | Fixed in 1.1.5; bounded continuing row-ID scans and exact control lookup are independent of the 100-row display. Tests cover 111 jobs; server restart/revocation uses the actual recovery path. |
| PA-015 | Fixed in 1.1.5; this pass uses actual Edge controls mutated to password/disabled/replacement nodes or changed link/form destinations and methods. Every changed target rejects; a stable fill succeeds. |
| PA-016 | Post-acquisition cancellation fixed in 1.1.5. Added cancellation/failure coverage before and during launch, context and page acquisition; all owned acquired resources close and no navigation is admitted. |
| PA-017 | Fixed in 1.1.5; handoff waits honor cancellation and propagate to the source while retaining late actual outcomes. Server revocation checks and existing shutdown/continuity tests are also run. |
| PA-018 | Fixed in 1.1.5 within filesystem guarantees: complete temporary write, flush, identity/version recheck, atomic replace, previous-byte retention and per-path serialization. Real Windows temporary-file tests check competing changes and queued cancellation. Unrelated software can still race the final rename; no perfect compare-and-swap guarantee is claimed. |

## Watchlist disposition

- W1, persistence cost: remains a measurement item; no unmeasured latency/battery claim.
- W2, coordinator complexity: no wholesale rewrite. The confirmed idle/checkpoint invariant is repaired at the existing ownership boundary.
- W3, retrieval relevance: remains a benchmark item; this audit does not establish recall quality or justify adding embeddings.
- W4, transport backpressure: existing bounded protocol fixtures pass; whole-response buffering is still not a proven peak-memory bound. No claim that hostile device-memory stress was performed.
- W5, helper lifetime: partial browser acquisition cleanup and duplicate simultaneous acquisition are now enforced and tested. This does not claim exhaustive OS process failure coverage.
- W6, idle/interruption ordering: reproduced in 30/30 trials, repaired, and passes 30/30 identical trials after the change. Idle now includes the final persistence checkpoint.
- W7, protocol drift: exact-number and complete-receipt tests strengthened, including commit scope. Not every independent Swift/JavaScript policy has been unified into one implementation.

## Validation commands and boundaries

Windows: `powershell -NoProfile -File scripts/Test-Core.ps1 -Integration`, `node --test Companion/test/*.test.mjs`, and `powershell -NoProfile -File Companion/test/updater.test.ps1`. Native Xcode workflow runs the Mac shared core plus the model/isolation/schema/account platform tests and model, recovery, settings and interaction UI flows. The build receipt records exact source/run IDs and counts.

This is a complete disposition of the supplied report, not a claim to have exhausted every interleaving suggested by it. The original baseline reproductions, pre-patch failures, post-patch logs and transport evidence stay in the local work directory. On-phone long-context inference, suspension duration, Apple profile acceptance and live GPT restoration remain separate physical/service checks. No live model inference or private production database mutation was part of these tests.

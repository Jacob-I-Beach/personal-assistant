# Completion of both supplied audits — 1.2.0

The remaining feasible implementation is complete. Release and simulator builds passed. All 21 native UI journeys and 34 platform/transport checks have passing coverage on the exact compiled app, including the recorded same-binary rechecks. Phone signing/installation and physical acceptance are separate.

The code audit targeted `54f2c3c`; the product audit targeted `f9ed6d1`. The supplied deliverable hashes and all 19 product-package hashes were verified. Recommendations were reconciled against the current implementation instead of treating every baseline observation as a new defect.

## Code audit

All 18 confirmed findings retain their regression coverage from 1.1.5/1.1.6. This batch reruns those tests and adds the remaining watchlist work. The detailed original-finding disposition remains in [AUDIT_116.md](AUDIT_116.md).

| Watch | Completed work |
| --- | --- |
| W1 | Transcript checkpoint cache skips unchanged payload encoding/SQL, invalidates on transcript or external-store writes, and is measured with real journal writes. Indexed Library and request-assembly costs are measured separately. |
| W2 | Typed presentation owner, exact execution identity, read-only browsing and a short transcript-mutation gate keep views and actions bound to their source. |
| W3 | Permission/status-filtered retrieval canaries, deterministic related-word fallback and source fingerprints. This is lexical retrieval, not an embedding-quality claim. |
| W4 | Bounded app-owned HTTP response buffers and a bounded streaming queue that fails explicitly on overflow; pinning/redirect tests cover the changed iPhone transport. No unmeasured total-process peak-RAM guarantee. |
| W5 | Browser ceiling, idle expiry, bounded observed handles, partial acquisition cleanup and active-action protection; real Edge tests. |
| W6 | Existing interruption/idle ordering regression remains tested. |
| W7 | Shared Swift/JavaScript argument and full-receipt fixtures, including exact integers, nullable fields, Unicode bounds and optional authority fields; original ownership/cancellation/context tests retained. |

## Product audit

| Item | Implementation |
| --- | --- |
| PX-01 | Derived first-use readiness, optional setup dismissal, preserved draft, direct ChatGPT/on-device choices. |
| PX-02 | Unfinished work and recent conversation/output precede compact entry actions; Home refresh remains automatic. |
| PX-03 | One CapabilityAvailability projection separates setup, catalog availability, blocked memory and a ready route; reused across Home, Models and Connections. |
| PX-04 | Direct New chat, visible Settings, a grouped workspace footer, collapsible folders, and distinct navigation identities. |
| PX-05 | Read-only saved-chat browsing preserves the active execution owner, Stop target and unsent draft; Return restores the active view. |
| PX-06 | Typed root PresentationState waits for actual dismissal, queues reviews without replacing an open editor, and restores task links without animation timers. |
| PX-07 | Real attachment selection/preview, source IDs, preparation/partial/unreadable states, per-file failures and model-specific pixel limitations. |
| PX-08 | Dictation no longer implicitly stops a response; speech callbacks, cutoff/finalization and owner checks preserve typed and recognized draft text. |
| PX-09 | One active task strip, actionable questions/reviews, saved sync/context recovery and expanded goal/action/output evidence. |
| PX-10 | Owned recovery states and local import/editor/export errors; uncertain receipts offer inspection instead of a replay button. |
| PX-11 | Quieter earlier-message actions, readable tool summaries, copy/read-aloud accessibility actions and stable reading position. |
| PX-12 | Canonical output projection carries identity, origin, revision, preview/location and protection; distinct same-name files remain distinct and full collections are uncapped at six. |
| PX-13 | Original document preview leads; CSV is literal, executable formats remain source views, and saved-versus-draft versions are explicit. |
| PX-14 | Files, documents, surfaces, projects, Inbox, planning items and images use a draft-preserving source-reference flow; image points and revisions survive handoff. |
| PX-15 | Locale-aware exact values obey the slider step; undo/reset, explicit unsaved conflict recovery, all-series selection, symbol distinctions and data tables. |
| PX-16 | Direct empty/current-chat project creation, goal/status/decision/question correction, output links and context-aware Continue; existing folder IDs preserved. |
| PX-17 | Separate title and message results, exact fingerprinted bounded landing, preserved query/position and labeled related-word fallback. |
| PX-18 | Incremental FTS index, filename/type/date/origin filters, excerpts, cancellation, empty states, rebuild and a measured 1,000-document fixture. |
| PX-19 | Searchable remembered context, tentative status, direct source-message inspection, correction/forget/undo; no unsubstantiated usage badges. |
| PX-20 | Pre-edit transcript/output snapshots, read-only history and explicit semantic-version-checked restore. Current access revocations survive; no old actions restart. |
| PX-21 | Persistent artifact drafts with base revision, compare/discard/resume, CAS save conflicts and committed-only export. |
| PX-22 | Grouped settings, validated immediate preferences and staged connection Apply/Cancel; dirty forms retain or explicitly discard changes. |
| PX-23 | Versioned local archive, explicit protected-data coverage review, integrity checks, isolated restore, retained libraries and deferred activation. Accounts, weights and executable queues excluded. |
| PX-24 | Separate unload, derived-cache removal and package/partial-download removal; bounded owned paths and measured stored bytes preserve personal work. |
| PX-25 | Retains the requested 64K default and actual model-supported controls; memory estimates and signing allowance stay distinct from measured inference. |
| PX-26 | Fast save-only Inbox capture, search, Unhandled/Filed filters, timestamps, move-to-chat/project and recoverable removal. |
| PX-27 | Selected calendar/reminder identity prepares context without performing a write; freshness and review checks remain at execution. |
| PX-28 | Ordinary photos support questions and coordinate selection; accessible normalized point controls retain alignment through zoom/rotation; depth remains measurement-specific. |
| PX-29 | Returning PC view leads with work, separate service readiness, actionable reviews/files, explicit Stop task versus service, accessible advanced setup and idle browser cleanup. |
| PX-30 | Shared semantic surfaces/spacing/actions/output/task components, system appearance, PC tokens, light/dark and contrast-aware controls. |
| PX-31 | Owned keyboard/modal transitions, explicit labels, large controls, reduced-motion behavior, exact chart/point alternatives and largest-text navigation tests. |
| PX-32 | All 28 proposed journeys reconciled to code/core/platform/UI/PC evidence; real audio, local inference, long suspension and human usability remain labeled physical checks. |

## Verification boundaries

The companion is already updated to 1.2.0. The same account, one pairing, 28 saved task identities, certificate and data folder were verified after an idle update and encrypted task-database backup. A fresh non-inference check found eight account models, including the selected model, with Python ready and pinned private HTTPS working. This does not claim a live model response was tested.

The phone package stays unsigned until the user installs it through the existing signer. Health and external notifications remain deliberately disabled. Actual memory allowance, sustained 64K inference, audio, sensor accuracy, VoiceOver use and an hour-long real network/lock transition require the phone. Formative usability and live answer-quality evaluation require a human/authorized live session.

The asynchronous transfer uses an explicit task delegate for its authentication and redirect callbacks, following [Apple’s bytes(for:delegate:) contract](https://developer.apple.com/documentation/foundation/urlsession/bytes%28for%3Adelegate%3A%29). The same pinned-certificate check is used at session and task level.

Archives contain readable selected work, not account credential stores. Their versioned format has bounded manifests/originals and rejects inconsistent identities, paths and checksums. Selecting another library takes effect at the next launch; the original remains available. Exports do not claim cloud synchronization or undo real-world actions.

# Personal Assistant 1.1.7 · Product journeys

Candidate following the supplied product/UX audit, based on packaged 1.1.6. This is one coherent native update; Apple signing and physical acceptance remain deferred.

## Added
- Exact-source context chips and draft-only Ask actions for files, surfaces, images, Inbox and planning items. Existing drafts require a merge confirmation; source versions and permissions are rechecked before model dispatch.
- Restorable document drafts with base revisions, comparison, discard and explicit saved revision history.
- Exact scenario values, reset/undo, full view and chart data tables; failed saves expose Retry/Revert and cannot be used as saved context.
- Exact history-result navigation and return to the retained query. Staged Library attachment selection with independent previews.

## Changed
- Voice input no longer cancels a running response; recognized text finalizes before Send, with conversation ownership checks.
- Files preview their original content first; CSV previews are literal tables. Library search runs off the UI actor and has explicit empty results.
- Ordinary preferences commit immediately with rollback on storage failure; advanced connection edits are a separate, discardable transaction.
- Home prioritizes waiting work; recent transcript controls are quieter; all chat outputs remain reachable without repeated six-item lists.
- Computer/account/model/computation readiness remain separate observations. The companion opens on work for returning users and follows system appearance and reduced-motion preferences.

## Removed
- Implicit send from ordinary contextual Ask, implicit Stop from microphone, misleading per-chat model-selection wording, fixed-delay Computer task navigation, and the general Settings saved modal.

## Still pending
- Native compile and UI evidence are being collected. Physical dictation, VoiceOver, model inference/memory and real service availability are separate checks.
- Full branching, portable backup/restore and separate read-only browsing while a response owns a chat need explicit data-model work. The audit disposition records the remaining proposals without calling them completed.
- Health, remote notifications and Live Activities remain deferred. Existing identity, data, pairing and downloads are preserved.

# Personal Assistant 1.1.7 · Product journeys

Version 1.1.7, build 22 is packaged from native source 100e00404c82a627bba9d9836330f67b4b525bb4. It includes the 1.1.6 fixes and this product/UX batch. Computer 1.1.7 release r2 is installed; Apple signing and physical acceptance remain deferred.

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
- Physical dictation, VoiceOver, model inference/memory and extended-lock/cellular behavior remain separate checks. Native builds and automated evidence are complete.
- Direct project creation/continuation, full branching, portable backup/restore and separate read-only browsing while a response owns a chat need explicit data-model work. The audit disposition records the remaining proposals without calling them completed.
- Health, remote notifications and Live Activities remain deferred. Existing identity, data, pairing and downloads are preserved.

## Validation

246 Windows and Mac core tests, 67 companion tests, 7 updater tests and 22 native platform tests pass. Twelve UI journeys have passing coverage against the final app. Main run 38649322248 provides the Release IPA, simulator and 11 UI passes; focused recheck 38651497096 establishes the typed draft before the microphone action and passes against the unchanged app. Recheck 38651932273 verifies actual PDF page content after loading, rather than only the toolbar. Both production-source checks identify 100e004. Final PDF, editor, search and context screenshots were visually inspected.

Earlier compile failures, a cancelled intermediate run and test-selector failures are retained in BuildValidation.json. The full workflow’s initial UI failure is not presented as an entirely green run. ReleaseValidation117.json ties the passing coverage to the final binary.

## Current computer observation

At 22:20 UTC on October 14, existing-account model discovery returned eight models including GPT-6.1-Sol. The account, pairing, 25 tasks, certificate, private network and actual Windows startup were preserved through the 1.1.7 update. No credentials were reset and no live model prompt was run. The cause of the earlier HTTP 520 is not established.

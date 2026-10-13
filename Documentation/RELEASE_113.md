# 1.1.3 build 18 — local-model isolation and paused external updates

Candidate October 13. Phone validation and installation are pending. The PC-only 1.1.2 r4 repair is already active and keeps PushWard disabled. Authenticated ChatGPT model discovery and inference currently return HTTP520; a redacted read-only capture identified an upstream Cloudflare response-parsing error. This release does not claim to repair that remote service.

## Added

- A focused scenario with an older saved GPT task and a new on-device message. The synthetic backend refuses any connected-model selection. Separate native checks exercise the actual Apple backend factory without running inference.
- A deliberate pause policy for the phone's external task notifications and Live Activities in the personal-signing build. It can be enabled later by the developer push configuration; local notifications are not technically dependent on paid enrollment.

## Changed

- Automatic computer-task recovery requires ChatGPT to be selected. Explicit recovery also refuses to restore a GPT backend underneath an AFM/downloaded/other-provider selection. A saved GPT task keeps its original model when ChatGPT is deliberately selected.
- Switching models clears stale task activity and connection notices. ChatGPT catalog refresh errors no longer appear as local-model reply status.
- The native backend factory continues to select Apple's on-device backend for a new AFM request, even with the computer connection enabled. The PC ledger showed an older GPT task restarting, not a new GPT job at the time of the report; the exact physical fresh-message reproduction remains unverified.
- The personal-signing build stops requesting task-notification permission, scheduling task alerts, registering activity tokens, creating native task Live Activities and requesting the large continued-processing banner. It clears previous app notifications and ends its earlier native task activities. Accepted computer jobs and in-chat questions/status remain independent of external delivery.
- Settings and the app's capability report reflect the pause. Health remains deferred.

## Removed from the active experience

- Silent restoration of a saved GPT backend while a local model is selected.
- Phone-side external task notifications and Live Activities during this deferred rollout. PushWard was already disconnected and its key cleared in the PC repair.

## Still pending

- Native build and focused validation, then a user-operated in-place phone update.
- Physical confirmation that a new AFM message stays local and no GPT recovery status takes over the chat.
- Recovery of the authenticated ChatGPT connection from HTTP520. No live-model test or alternate billing path is authorized or used.

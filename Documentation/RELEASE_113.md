# 1.1.3 build 18 — local-model isolation and paused external updates

Packaged and verified October 13. The device archive is from source `7ffdfbfd3c872f65c1b0f2d1b3f649f91528cad2`, run `38475203635`; its Standard IPA SHA-256 is `6ea3b287ccf8c7d95bd7999d02b70b1fe3a1abd606e6f6525c072069137a917d`. Physical installation remains pending. The PC-only 1.1.2 r4 repair is already active and keeps PushWard disabled. Authenticated ChatGPT model discovery and inference returned HTTP520; a redacted read-only capture identified an upstream Cloudflare response-parsing error. The final model-list check at 22:49 UTC still failed. This release does not claim to repair that remote service.

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

- A user-operated in-place phone update with the same signing account and installed bundle identity.
- Physical confirmation that a new AFM message stays local and no GPT recovery status takes over the chat.
- Recovery of the authenticated ChatGPT connection from HTTP520. No live-model test or alternate billing path is authorized or used.

## Verification

The physical-device archive and simulator build succeeded. Run `38477001942` passed 202 Mac shared-core checks and eight native platform checks. UI recheck `38479449366` passed the new local-message/paused-settings scenario using the unchanged app; both screenshots were inspected. The existing 202-check Windows shared-core baseline remains applicable because no shared-core source changed. The active PC r4 repair passes 38 companion checks and its deferred-delivery UI check.

Two validation issues were confined to tests: an omitted required lifecycle argument, then a UI assertion that expected a temporary fixture name which scene activation replaced with the simulator's standard Apple model name. The corrected UI test verifies the stable on-device location label and a saved GPT task before sending. The actual phone archive was not rebuilt for either correction. The scene uses a synthetic local response; it does not establish physical AFM inference quality or prove the exact reported fresh-message reproduction.

See ReleaseValidation113.json and DeviceValidation113.json for the evidence and remaining phone checks. No new ChatGPT sign-in, PC pairing, API billing or PushWard test is required for this package.

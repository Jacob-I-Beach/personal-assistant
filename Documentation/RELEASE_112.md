# 1.1.2 build 17 — remote activity delivery and visible outputs

Prepared October 13, 2026. The physical-device archive is from source `4e8e58812e1b8afaef9b927e9ebace1678231816`, native run 38373464461. PC package `1.1.2-release-r3` is installed from code revision `ed6104976c6953054313b10989c9783a854b84bd`, with the existing account, pairing and saved tasks. Includes the complete 1.1.1 repairs; this is one phone update. Physical installation remains pending. The Standard IPA SHA-256 is `70c7c8f16f4b752aaa119064ba30bbfe81e48c01ac0d4f16cd62c4b323dd9c49`.

## Added

- An optional PushWard connection in the PC control center. Jacob chose its free tier and reports the iPhone app installed, signed in, with Notifications and Live Activities allowed. The integration key is entered locally, checked for the needed permissions, and stored through the existing encrypted vault. It never enters a model prompt or the public source repository.
- Remote Live Activity state, attention/completion alerts, a synthetic delivery test, usage display and disconnect controls. Test cards expire after two minutes and can also be cleared explicitly. Only fixed status phrases and task links leave the PC; conversation text, questions, captures, Health records and files are not sent to PushWard.
- Native task links with saved server/job identity. An existing chat opens directly; a scheduled result can be imported from its original paired PC before opening. Links do not supply credentials, execute actions or approve reviews.
- An explicit **Open chat** action on expanded PushWard notifications. A normal tap on a notification body still opens PushWard's detail screen, as observed on Jacob's phone; the detail's Link then opens the correct chat. The explicit action and activity button are the documented direct-app routes and need their own phone confirmation.
- `publish_task_files`: an explicit publication tool for screenshots, rendered document pages, charts and other saved outputs. It validates ownership, preserves source bytes/versions, and reuses an identical publication. The native transcript puts published files outside the tool disclosure, downloads them during synchronization, and renders bitmap images inline with full-size Quick Look.

## Changed

- The enabled bridge owns external task presentation, avoiding a duplicate native Live Activity. The original native path remains available when the bridge is disconnected. PC work continues independently of any notification delivery error.
- PushWard's generic percentage layout is replaced with its status/alert layout after the physical test showed a misleading 0%. The leading symbol follows actual research, Python, documents, browser/desktop, writing, waiting and completion events. The trailing label shows status, including a ready check; these templates do not expose a custom looping spinner. A queued, obsolete phase is replaced if work has moved on before delivery.
- The free-plan adapter coalesces routine updates, allows up to four routine phases per task, prioritizes questions/completion, and reads the provider's actual quota counters. It does not buy a plan or add API billing. The advertised free allowance is 250 Live Activity updates and 500 ordinary notifications per UTC month; this is updates, not tasks.
- A ready card uses a green checkmark and a task link, then ends when its result is opened through that link, finishes while its chat is visible, or a later task replaces it. Opening an active task does not end its activity. Ready cards have a two-hour expiry; iOS and PushWard still govern lifetime, animation, delivery and competing activities. This is a bridge-owned ActivityKit surface, not custom code inside Personal Assistant's widget extension.
- The latest reported immediate failure was accompanied by the retained provider code `server_is_overloaded`. The prior worker collapsed it into a generic saved-progress error. Recognized busy errors now retry the same model request twice, after 5 and 15 seconds, before returning a specific explanation. No partial tool call is executed and no completed effect is repeated by this retry.
- Unknown provider failures retain bounded code/status/parameter diagnostics without recording raw error bodies or conversation contents.
- Image-only presentation messages no longer generate empty provider messages. Inspection files remain working material until explicitly published; the model is told to use the publication tool when the user asks to see one.
- Windows startup registration now uses and verifies the actual user registry through CIM. Ordinary writes from the packaged Codex environment had reached a virtual registry view. The installed startup entry now points to r3; no new sign-in, pairing or firewall grant was needed.
- This package includes 1.1.1's shared account email/sign-in display, compact app/tool instructions, implicit Python `assistant` helper, faithful streaming-state replay and same-job/original-model recovery.

## Removed

- Generic local-failure wording for known provider overloads.
- The implicit assumption that a screenshot inspected by the model has appeared in the user's chat.
- Duplicate final attachments for already-published files and duplicate alerts on repeated task-state events.
- The synthetic test's misleading percentage and indefinite appearance, and the claim that every ordinary PushWard notification-body tap directly opens Personal Assistant.

## Validation and remaining work

Validation is recorded in ReleaseValidation112.json: 202 shared-core checks on Windows and macOS; two native bridge/profile tests; 36 companion checks; seven updater checks; and synthetic Edge setup/test/clear controls. The device archive, ARM64 platform, build number, file hash and retained Activity extension were inspected. Quick Look displayed the actual full-size synthetic image, while two earlier UI assertions incorrectly required hidden controls/internal accessibility nodes. Focused recheck 38378990326 passed against the unchanged app, rebuilding only the test bundle. It checks inline display and opening the full-screen controller; full-image visual evidence comes from the prior unchanged-app run, since the final capture caught the preview before its asynchronous image appeared. No paid or live-model request is part of verification.

The PC update was explicitly authorized and completed successfully. PushWard is connected through the encrypted vault. Jacob confirms delivery of the Live Activity and regular alert, plus correct-chat opening through the detail's Link. The revised status/action test was accepted by the provider; physical confirmation of that action remains pending. At the final quota check, the account reported 5/250 activity updates and 3/500 alerts used. No purchase or upgrade was made.

The source supports both bridge delivery and future directly provisioned APNs. Web Push alone supplies regular alerts but not native ActivityKit updates. Research found that PushWard documents custom-scheme tap actions; Notify! is free but its documented activity button is HTTPS-only, while Hark lists Live Activities under Pro. No other provider was activated.

Physical build17 installation, actual completed-card dismissal, the new direct action, extended background/lock behavior and normal-use answer quality remain device acceptance checks. Exact looping-spinner customization is not available in the bridge templates. Phone signing/install remain user-operated. Keep the existing account, pairing, task database, signing identity and app data; Health and native APNs provisioning remain deferred.

Sources checked October 13, 2026: [PushWard activity API](https://pushward.app/docs/api/activities), [alert/status layout](https://pushward.app/docs/live-activities/alert), [notification actions](https://pushward.app/docs/notifications/actions), [authentication and quota fields](https://pushward.app/docs/api/authentication), [limits](https://pushward.app/docs/limits), [Apple ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [WebKit Web Push](https://webkit.org/blog/16535/meet-declarative-web-push/).

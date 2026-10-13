# 1.1.2 build 17 — remote activity delivery and visible outputs

Candidate dated October 13, 2026. Native validation and physical acceptance are pending. Includes the complete 1.1.1 repairs; this is one coherent update, not a request to install two phone builds.

## Added

- An optional PushWard connection in the PC control center. Jacob chose its free tier and reports the iPhone app installed, signed in, with Notifications and Live Activities allowed. The integration key is entered locally, checked for the needed permissions, and stored through the existing encrypted vault. It never enters a model prompt or the public source repository.
- Remote Live Activity state, attention/completion alerts, a synthetic delivery test, usage display and disconnect controls. Only fixed status phrases and task links leave the PC; conversation text, questions, captures, Health records and files are not sent to PushWard.
- Native task links with saved server/job identity. An existing chat opens directly; a scheduled result can be imported from its original paired PC before opening. Links do not supply credentials, execute actions or approve reviews.
- `publish_task_files`: an explicit publication tool for screenshots, rendered document pages, charts and other saved outputs. It validates ownership, preserves source bytes/versions, and reuses an identical publication. The native transcript puts published files outside the tool disclosure, downloads them during synchronization, and renders bitmap images inline with full-size Quick Look.

## Changed

- The enabled bridge owns external task presentation, avoiding a duplicate native Live Activity. The original native path remains available when the bridge is disconnected. PC work continues independently of any notification delivery error.
- The free-plan adapter coalesces routine updates, allows up to four routine phases per task, prioritizes questions/completion, and reads the provider's actual quota counters. It does not buy a plan or add API billing. The advertised free allowance is 250 Live Activity updates and 500 ordinary notifications per UTC month; this is updates, not tasks.
- A ready card uses a green checkmark and a task link, then ends when its result is viewed or a later task replaces it. iOS and PushWard still govern presentation lifetime, animation, delivery and competing activities. This is a bridge-owned ActivityKit surface, not custom code inside Personal Assistant's widget extension.
- The latest reported immediate failure was accompanied by the retained provider code `server_is_overloaded`. The prior worker collapsed it into a generic saved-progress error. Recognized busy errors now retry the same model request twice, after 5 and 15 seconds, before returning a specific explanation. No partial tool call is executed and no completed effect is repeated by this retry.
- Unknown provider failures retain bounded code/status/parameter diagnostics without recording raw error bodies or conversation contents.
- Image-only presentation messages no longer generate empty provider messages. Inspection files remain working material until explicitly published; the model is told to use the publication tool when the user asks to see one.

## Removed

- Generic local-failure wording for known provider overloads.
- The implicit assumption that a screenshot inspected by the model has appeared in the user's chat.
- Duplicate final attachments for already-published files and duplicate alerts on repeated task-state events.

## Validation and remaining work

Local shared-core, companion, native compile and focused image/routing validation will be recorded in ReleaseValidation112.json. No paid or live-model request is part of automated verification. Synthetic notification tests use a mock provider until the user configures PushWard and deliberately requests the connection test.

The source supports both bridge delivery and future directly provisioned APNs. Web Push alone supplies regular alerts but not native ActivityKit updates. Research found that PushWard documents custom-scheme tap actions; Notify! is free but its documented activity button is HTTPS-only, while Hark lists Live Activities under Pro. No other provider was activated.

Actual PushWard display, correct-chat tap, background/lock behavior, exact animation and free-quota operation remain device acceptance checks. The PC updater, integration-key entry and phone signing/install are user-operated. Keep the existing account, pairing, task database, signing identity and app data.

Sources checked October 13, 2026: [PushWard activity API](https://pushward.app/docs/api/activities), [authentication and quota fields](https://pushward.app/docs/api/authentication), [limits](https://pushward.app/docs/limits), [Apple ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [WebKit Web Push](https://webkit.org/blog/16535/meet-declarative-web-push/).

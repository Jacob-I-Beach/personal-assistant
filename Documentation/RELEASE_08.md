# 0.8: one coherent workspace

Source candidate: 0.8.0 build 9. The installed 0.7.1 crash repair remains the last phone-confirmed version until the new native build and device checks pass.

For an explicit request-by-request account of what was implemented, only partially implemented, deferred or not yet proven, see [the implementation audit](REQUEST_AUDIT_08.md). The original Health helper had a production-interface packaging error; revision 2 corrects it and the user confirmed its normal interface opens. Actual Health provisioning and background continuation remain unverified on the phone.

## Conversation and navigation

The composer uses its full width, with a separate control row. The chat toolbar no longer duplicates New Chat or Settings; New Chat and Settings remain in the sidebar. Library is the same destination from the plus menu, chat menu, sidebar and Home. File details can attach to the current chat and return to it. Connections brings planning, location/weather, Health, folders, models and Watch requests into one place, with plain descriptions of their purposes.

Jump to latest now performs an immediate scroll and preserves controller ownership when SwiftUI replaces an older hosting controller. Tool, web and source disclosures pin the heading that was tapped before changing height. Nested groups use indentation, a leading rule and a quiet card background. Saved text renders Markdown; routine internal fields stay in the diagnostic copy. A single saved result opens directly instead of adding an unnecessary wrapper disclosure.

Message actions have matching 44-point targets, a pressed state, and a visible Copied confirmation. Settings selections, sending, copying, the first reply and questions have deliberately light feedback. Questions use three soft taps. Feedback is foreground-only, rate-limited, and can be disabled. Haptic feel requires actual phone review.

## Context and app awareness

Sending ordinary content to the selected connection starts the request without another per-chat confirmation. An optional setting restores confirmation. Explicit revocation and Health sharing still require review; on-device-only restrictions remain enforced.

Working context is a per-model/account preference in the model picker. Account-advertised capacity overrides published limits. Verified GPT-6 Astra, GPT-6.1 Sol and GPT-6 Luna documentation supports a 1.05M total window; the UI allows up to 1M input tokens while preserving space for output. Unknown models use a conservative default. The planner uses an approximate text-to-token budget, and the provider remains authoritative. Complete stored conversations are not truncated. A context-limited saved task can be manually resumed after a real budget increase; completed/unknown operations retain their replay protections.

A small app-authored orientation describes navigation, existing capabilities and current connection preferences. It contains no personal record dump. The model can use it without routinely rediscovering the whole registry; exact tool schemas remain discoverable and permissions remain app-enforced.

## Background work

The phone reproduction established that iOS granted a continued-processing assertion; the filtered trace did not establish the precise expiration reason. The previous progress path only counted visible text and missed network activity before a public answer. The new path reports actual received response bytes and tool-result bytes, with no timer-generated progress, fake percentage or ETA. Submission uses the asynchronous scheduler API, callbacks explicitly handle concurrency, and the identifier family comes from the installed plist. Task-correlated lifecycle diagnostics record states, counts and error codes without exporting prompts or account/device identifiers.

The system provides the activity and its compact/expanded presentation. iOS controls its gestures and resource allocation. A Live Activity is not a server-side worker, a background GPU entitlement, or a guarantee that unlimited silent network waits survive suspension. The actual phone check must include reasoning, tool use, streamed text, Home/app switching, and returning through the system activity. Force quitting remains different from ordinary backgrounding.

## Health with personal signing

Apple's current capability table lists HealthKit for nonpaid Apple Developer accounts. The existing official iLoader route does not request this capability, and the installed build 8 was verified to lack the HealthKit entitlement. A narrowly modified local iLoader build requests Apple's HealthKit feature only for this app's explicitly Health-enabled IPA, verifies that Apple returns the capability, and verifies the downloaded provisioning profile before signing. Authentication, account storage and signing identity use the pinned upstream code. The helper has compiled and its two scope tests pass; the actual account provisioning and device Health authorization still need user-operated verification.

The native workflow produces both a normal iPhone signing input and a separately marked HealthKit input with the same compiled executable. Health UI also checks the installed embedded profile before presenting a Health read request. Missing entitlement never becomes a HealthKit call that could crash. The profile hint is not read permission: iOS still verifies signatures and the user still chooses shared Health types. Previous app data and signing identity must be retained.

## Decisions on the supplied capability audit

- Contacts lookup and disambiguation are a worthwhile next integration. Existing person-name strings should not be guessed into phone numbers. Keep a user-selected contact reference and explicit aliases.
- Share extension capture is worthwhile after this stability batch. Existing Siri/Shortcuts Inbox routing remains available; a separate Share extension is not claimed here.
- Email composition with attachments is useful next. Direct artifact sharing already exists through the native share sheet, so it does not need a duplicate export system. Mailbox reading is a separate authenticated connection.
- Scheduled assistant runs need a real execution host and bounded triggers. Calendar reminders and local notifications do not imply future model execution. Recurrence and location-triggered reminders deserve their own reviewed edit semantics.
- Conversational voice is a separate transport/interaction project. Current dictation and read-aloud remain available; no realtime speech-to-speech capability is claimed.
- Richer document tools are useful, particularly page/cell references and verified output layout. Existing original-file sharing, previews, CSV/PDF generation and native working surfaces should be improved rather than duplicated.
- Outcome receipts, duplicate prevention, question cards, task history and version-checked edits already exist. The new interaction regression checks and lifecycle diagnostics strengthen those foundations.

## Validation policy and acceptance

Jacob explicitly chose to keep the source repository public. `xcode-27` is a standard GitHub-hosted runner; public-repository standard compute is free under GitHub's current policy. Verify visibility and runner class before dispatch. The older ledger is a fully-billable list-price estimate, not net account charges. Personal billing API results remain outside Git. Artifacts use short retention; storage is separate from compute.

The initial validation target included shared-core tests, native EventKit tests, platform tests, all interface scenarios, native screenshot inspection, a matching Release build, package/metadata checks and helper provenance. After the user asked whether further testing was needed, the candidate was delivered with the corrected-but-unrerun connected-folder/export UI scenario explicitly pending. Before phone completion claims: install in place, retain chats, establish background continuation and island behavior, and verify the actual Health entitlement and user-authorized overview. Haptic feel remains a physical observation.

Sources: [OpenAI models](https://developers.openai.com/api/docs/models), [GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol), [Apple continued processing](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados), [Apple progress discussion](https://developer.apple.com/forums/thread/805554), [Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [Apple capability table](https://developer.apple.com/help/account/reference/supported-capabilities-ios), [official iLoader](https://github.com/nab138/iloader), [community HealthKit provisioning reference](https://github.com/Rzbck/iloader-watch-companion), [GitHub standard runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [GitHub billing policy](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

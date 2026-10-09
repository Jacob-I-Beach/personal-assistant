# Next substantial release: engineering record

Started October 9, 2026, after Jacob approved continuing from PRODUCT_DESIGN.md. This record distinguishes implemented source, synthetic verification, native validation, and physical-device evidence. The installed 0.1.0 app is not being replaced by each internal iteration.

## Source work underway

- Embedded pinned QuickJS-NG 0.17.0, without its libc/OS modules, workers, native bridge, or bytecode loader. Each script gets a fresh realm, a 64 MiB heap, bounded stack/input/output, deadline and cooperative engine interrupt, and cancellation. It accepts JSON and returns JSON/text artifacts. No general Python environment or cloud sandbox is claimed.
- SQLite 3.54.0 with WAL, transactions, per-message records, FTS5 history search, retained legacy JSON originals, one-time import, and durable artifact revisions. Source packages and license provenance are in Dependencies/NOTICE.md.
- A bounded working-context selector retains whole conversational turns and leaves older source messages searchable. Its generic budget is deliberately a UTF-8 estimate, not exact tokenizer accounting. Provider-specific refinement and long tool-result handling remain to validate.
- Common app-owned tools: saved capture reads, exact history search/read, JavaScript execution, and text artifact creation.
- Portable ChatGPT registration/callback/claims/model-catalog contracts, account-scoped request authorization, and namespaced Responses tools. Native source uses Apple's authentication browser and loopback listener, JOSESwift for RSA signature verification, CryptoKit/Security for PKCE randomness, and Keychain for separate account registrations and rotating tokens.
- Apple Foundation Models adapter source, with native Tool callbacks routed through the same app-owned executor. Direct PCC remains disabled until the signed app's managed entitlement is established. Jacob reports consumer or developer PCC access; the precise route is still unanswered.
- A pinned local catalog for Qwen 3.5 2B, 4B, and 9B. Published metadata and weight hashes are checked. Downloads do not load the model automatically, and their task is independent from a ChatGPT conversation.
- Native conversation, model picker, history search, editable artifact library, and settings are being rebuilt. MarkdownUI supplies rendering; both remote image providers are disabled. Drafts are retained until a user message has actually been saved.

## Verified so far

The Windows shared-core suite passed 39 tests after the portable storage, context, sandbox, and authorization changes. It includes a 1,000-message saved conversation, exact-source search, stale-index removal, rollback on identity collision, legacy import without stale reimport, loop/cancellation/memory/stack/output/path limits, offline host-API absence, durable script artifacts, account callback/state binding, and prior streaming/cancellation/HTTP fixtures. These tests use synthetic data and no paid model APIs.

Apple’s current supported-capabilities HTML lists HealthKit for ADP, ADEP, and free Apple Developer membership. This is more favorable than older assumptions, but the actual iLoader signing route still needs verification. No paid enrollment has been performed.

## Required next checks

Internal validation update: the first new Mac job, `37989208475` at source `b0951ea`, passed the shared-core suite and stopped during native compilation because JOSESwift's generic header accessor was not public. The adapter now inspects only the header's encoding flag with ordinary JSON parsing and still delegates signature verification to JOSESwift. The run used 7 rounded Mac minutes, bringing the known total to 30 minutes (about $1.86 if billable). No device package was produced.

The second source batch adds a direct HealthKit overview, explicit Health-derived network consent, an on-device-only setting, local speech dictation/read-aloud, a Watch companion with persistent request deduplication and interruption recovery, and Files import of matching verified MLX packages. The shared Windows suite now passes 44 tests. Health aggregation tests cover overlapping samples, missing data, and daylight-saving boundaries; Watch tests cover duplicate delivery and persisted replies. Voice, Health authorization, Watch signing/delivery, and actual iOS behavior still require native/device validation.

1. Compile the changed native app and run native UI/authorization fixture tests on the hosted Mac. Windows parsing is insufficient.
2. Inspect actual native screenshots in light/dark/large-type and common interaction states; correct issues before creating a device release.
3. Complete model import, documents/memory, useful Apple health/organizer and Watch workflows, and voice against the same scope and persistence rules. Do not present incomplete controls as working features.
4. Exercise real ChatGPT authorization, Apple availability/PCC entitlement, local-model inference, and hardware performance on the phone as part of the substantial device validation, without describing synthetic tests as real account or sensor evidence.
5. Preserve app identity, existing data, and model files through the update. Complete migration/recovery and native signing checks before packaging.

## Build spending

The second native job, `37991960595` at source `28e2f6a`, succeeded: 44 shared-core tests on macOS, iPhone and Watch compilation, two iOS platform tests (real loopback callback and signature validation), and two native UI tests. The actual platform tests took about 0.15 seconds and UI tests about 43 seconds. Xcode then spent 600 seconds timing out during optional simulator diagnostics; subsequent runs disable that diagnostics collection while retaining logs, results, and screenshots. This job used 19 rounded minutes, bringing known usage to 49 minutes, about $3.04 if entirely billable.

Screenshot review caught a catalog total of zero bytes even though its individual file sizes/hashes were correct. The totals are repaired and a bundled-catalog invariant test is added. UI contrast and code-block presentation are being refined. The next candidate also adds saved-memory editing with per-note connected-model permission, protection for answers derived from on-device-only memory, artifact-draft recovery, interruptible credential-refresh waiting, a Siri/Shortcuts entry point, and direct Health refresh tools within authorized conversations. The current Windows suite has 50 passing tests. These later changes still need their own native validation.

The prior verified estimate was 23 rounded Mac minutes, approximately $1.43 if entirely billable, against Jacob's authorized $5 validation budget. Before dispatching further jobs, inspect current run history. Bound each new Mac job's timeout so the remaining authorization cannot be consumed by an unbounded retry loop. No new cloud workspace or paid service is being provisioned.

## Release packaging and final inspection

Run `38001440054` at `d6339a3` passed 50 macOS core tests, three native platform tests, three native UI tests, and the complete iPhone/Watch Release build. Disabling optional test diagnostics removed the previous 600-second stall. This run took 16 rounded minutes; the known cumulative total is now 65 minutes, approximately $4.03 if fully billable.

Visual review caught a white-on-white prominent button in dark mode, a theme modifier hiding the custom code-block header, and a welcome image incorrectly loaded as a loose resource. The final batch explicitly sets contrasting button text, fixes the Markdown theme's modifier order, moves the image into the asset catalog, and verifies the Copy control and image loading in native tests.

Review of the exact official iLoader 2.3.6 / isideload 0.4.3 source established that this installation route does not provision the embedded Watch or request HealthKit. The complete build is retained, and a separate iPhone-only signing input omits the Watch directory while preserving every retained file's bytes. Health requests fail clearly before any authorization/query in this deployment. The detailed installation boundary and user-operated test steps are in DEVICE_VALIDATION.md. No unofficial signer was installed or given credentials.

The final native job is capped at 15 minutes. Along with the existing 65 rounded minutes, its compute ceiling is approximately $4.96, within the previously authorized $5. Redundant generic simulator compilation is removed because the native test step builds the actual app and its dependencies itself. This is a bounded estimate, not a reading of GitHub's billing account.

Observed platform follow-ups: Xcode emitted a nonfatal App Intents SSU archive diagnostic even though `Metadata.appintents/extract.actionsdata` and the generated SSU YAML are bundled. Siri phrase discovery is therefore not validated by a successful build. The voice adapter also emits an iOS 27 deprecation warning for the audio tap and a main-thread audio-session activation warning during simulator navigation; actual voice routing and responsiveness remain in the physical validation pass. Do not describe either area as fully verified or suppress these diagnostics to claim completion.

Final outcome: run `38003037939`, source `c403e184dc2bfbeb5d4c776e24d4334bec112895`, succeeded at 23:24:29 UTC on October 9, 2026. It passed 50 macOS core tests, four native platform tests, three UI tests, and the Release build. Its changed screens were visually inspected: the welcome asset is visible, the dark-mode ChatGPT label has contrast, the code header/Copy control appears, and the Health limitation is explicit. The native tests also check that the unprovisioned Health build rejects requests before authorization or queries.

Both packages were downloaded, their SHA-256/ZIP/Mach-O metadata checked, and the phone executable's equality between archives confirmed. The iPhone-only input is 13,431,742 bytes with SHA-256 `579b90fd6f679bd864a36bd61f5040ad5302e89e167000d5ffb8b211e26d5333`. Eight native screenshots and package receipts are retained locally. The run used 15 rounded minutes, bringing all known Mac compute to 80 rounded minutes, an estimated $4.96 if fully billable. Native test compilation still builds package variants; removing the separate generic compile reduced this run to 14 minutes 21 seconds overall but did not eliminate all duplicated package compilation.

Jacob's first manual iLoader import stopped with HTTP 502 from the selected SideStore (.io) anisette helper before developer-device listing completed. After switching to the official built-in SideStore (.app) preset and renewing the iLoader session as instructed, he confirmed that the update installed and Version 0.2.0 opens. This establishes user-reported physical installation/launch. Live model/account behavior and the requested JavaScript-to-CSV test remain awaiting his report. No GUI automation is being performed following his preference change.

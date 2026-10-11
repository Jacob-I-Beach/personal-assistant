# 0.9.0 build 10 — response controls, questions and Health

Packaged candidate from `6a681c168a11743fb4d28276a2598b6d245b7f81`. Focused native validation is complete; phone installation is pending. User reports confirm the prior 0.8 interactions generally work, with the specific new exceptions below; see DeviceValidation08.json. Personal screenshots and records remain outside Git.

## Added

- A progressively colored brain in the composer opens thinking and working-context settings together. Choices are retained per model; context uses the current connection's capacity information.
- Connected Health data selection with search and Select all available. The catalog currently describes 219 public HealthKit types: quantities, categories, characteristics, correlations, clinical records when provisioned, and supported specialist records. Availability is resolved on the device; the catalog is not a claim that every type has shared records.
- `list_health_types` and `read_health_data` expose relevant selected types and bounded date ranges. Quantities support daily totals/averages and sample reads; specialist data includes medication records, activity summaries, vision, hearing, ECG, state of mind, assessments and bounded route/heartbeat series. Records remain protected by HealthKit, app selection, conversation sharing and the Health-data backup policy. Clinical data requires the actual profile capability. Some Health-app features are not exposed by HealthKit.
- A one-shot saved destination returns a cold-started app to work left in the background. It routes to existing work without creating another user message or automatically repeating external actions.
- Diagnostic categories distinguish working-context pressure, model reply limits, network timeout, early stream ending, work-session limits, waiting for input and a system-ended/cancelled background session.

## Changed

- The model catalog's default context window no longer acts as a universal maximum. A separate advertised maximum is parsed; documented known-model capacity is used when no explicit maximum is supplied. A real connection maximum can be lower than the published API model capacity and remains visible. The input budget is approximate and reserves response space; choosing a larger input window leaves less room for reasoning/output.
- Questions open as a medium-height, expandable, scrollable sheet with a persistent answer footer. Large accessibility text starts expanded. Selecting a choice is separate from typing Something else. The answer button has explicit contrasting foreground/background colors.
- Answered questions remain visible directly before their user answer in the transcript, outside collapsed tool activity. Existing stored question receipts benefit from the same presentation.
- Question/review waits finish the current background processing segment normally. Answering can begin another segment. The saved task remains waiting; this is not a claim that its goal was completed.
- Deliberate manual continuation works after the old three-resume/twelve-total-round limits. Automatic recovery remains bounded, each work session retains round/tool limits, completed receipts are reused, and unknown effects are not blindly repeated.
- Network idle allowance rises from two to fifteen minutes, with a separate one-hour resource bound. This fixes a confirmed client setting, not a proven diagnosis of the user's intermittent failure. Raw byte activity no longer emits redundant full transcript updates.
- Background-return routing waits for initialization and keeps a task-opening view in front of the fresh Home view. Question notifications carry the question text. Normal fresh starts without a saved background destination remain fresh conversations.
- The weekly Health overview respects the types selected in the broader connection. Connected-model Health reads can request a concrete conversation-sharing review when needed.
- Health search collapses the introduction while filtering, keeping matching categories above the keyboard and retaining the selection count and save action.

## Removed

- The circular thinking control and its Max text badge.
- Working context as a separate action in the model picker; saved-work guidance opens the same brain panel.
- Library from the three-dot chat menu. Library remains in the plus menu and sidebar.
- Choice text being copied into the custom-answer field.
- The lifetime continuation limit that removed the Continue button after repeated interruptions.

## Still pending and physical limits

- Native typecheck, screenshot review and the matching archive passed. Passed 177 core and eight EventKit checks in [the final run](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38152677219). The four focused interface scenarios have passing coverage: 1 in the final run, with three previously passing scenarios and 36 platform checks retained from [run 38149397041](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38149397041) against unchanged production paths for those checks. The final run covers the Health selection view, including results visible above the keyboard. Physical results remain pending.
- The exact cause of each observed background failure is unconfirmed. The old implementation had several independent limits: catalog-derived context/reply budgets, a two-minute client idle timeout, bounded rounds/resumes and iOS processing grants. The updated diagnostics preserve these distinctions. Do not label the user's experience a crash or timeout without evidence.
- Long quiet reasoning and lock-screen continuation remain subject to iOS execution grants. The existing system continued-processing activity supplies the system presentation; no fake progress, silent audio mode or remote worker is introduced. A fully powered-off phone cannot run local work.
- The ChatGPT plan authentication route requires streaming requests with `store:false`; server-stored background Responses are not silently substituted. Any different execution host would be a separate change.
- Real Health authorization, available records, locked-device restrictions and clinical access are device/provider facts. Empty reads do not reveal denial versus no data. Series and large records report partial coverage instead of pretending a bounded response is the entire history.

## Evidence and targeted validation

The new core cases cover default versus maximum catalog capacity, a 1M-capable fixture and a smaller 252k-input fixture, a fourth deliberate continuation after the old limits, an inline question before its answer, and bounded Health queries. Native checks target the brain panel, compact question, Health catalog and return-to-work paths. Prior phone-confirmed behavior is retained; this is not a promise that every existing interface scenario will be repeated.

Primary references: [model capacity](https://developers.openai.com/api/docs/models/gpt-6-astra), [ChatGPT plan inference requirements](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference), [Apple continued-processing progress guidance](https://developer.apple.com/forums/thread/805554), [HealthKit data types](https://developer.apple.com/documentation/healthkit/data-types). The catalog links each regular type to its Apple reference.

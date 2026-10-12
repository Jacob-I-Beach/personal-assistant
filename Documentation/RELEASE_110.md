# Personal Assistant 1.1.0 · Build 15

Status: source candidate. Native compilation, packaged installation and physical iPhone acceptance are separate checks; the final evidence record will identify each.

## Added

- Computer files with task-scoped folder grants, version-checked edits and saved previous versions; reviewed PowerShell execution with process-tree cancellation and bounded output.
- Windows desktop screenshots and observed controls, with fresh observation IDs, exact-action review and refusal to target a locked/secure desktop. The helper runs as the normal user.
- A separate Edge task browser with real screenshots and observed element IDs. Interaction reviews bind the actual page/control. It does not import normal-browser sessions or automate password entry.
- Computer task detail, review and output-download controls in the local control center.
- Encrypted APNs configuration, per-task device/ActivityKit token registration, server-derived activity state, completion/attention alerts and conversation routing. Live delivery is **not provisioned** in the personal-signing package.
- An internal developer build configuration requesting push and increased memory entitlements. Use only after the actual Apple provisioning profile grants those capabilities; it is not an App Store configuration or proof of a memory allowance.
- Qwen 3.5 4B memory-aware local context controls, a 4/6/8 GiB ceiling, compressed KV cache, bounded prompt prefill and an exact prepared-token check. The model remains on the iPhone. Memory estimates are not physical-device measurements.

## Changed

- When the Computer connection is enabled, ChatGPT tasks belong to the PC from Send. A durable request key and required-input manifest allow the PC to start without a later phone start command. The phone never hands over a running direct request merely because it backgrounds.
- Reconnection follows the existing task. A lost subscription does not establish task failure or completion. Unfinished server work can recover after a service restart, retaining operation receipts and pending reviews.
- The native Live Activity represents the assistant task; server-owned work does not start an iOS continued-processing task to own remote inference.
- The model catalog comes from the PC's authorized ChatGPT account and preserves advertised context/reasoning metadata. No API billing or PC-hosted local model service is configured.
- Permitted current-chat and memory snapshots support bounded server-side retrieval. Plans and task records stay available without the phone. Unshared, absent and phone-only sources retain their permission and availability boundaries.
- Python can request up to 8 GiB, eight CPU cores and 30 minutes; defaults remain smaller. Host GPU programs are available through reviewed commands, with hardware inventory reported separately from installed software support.
- Model downloads use exact pinned files, disk-backed transfer, byte progress, completed-file reuse, supported resume data and checksum verification. Wi-Fi-only failures explain the cellular setting, now exposed in Models.
- Local models use compact tool discovery and retain the upstream Qwen tokenizer, tool-call and reasoning configuration.

## Removed

- Automatic foreground-to-background model ownership transfer for new computer-connected turns.
- The fixed 24,000-byte context cap for downloaded models.
- Reliance on the model-download hub wrapper's aggregate progress to indicate an active file transfer.

## Still pending / requirements

- Apple Developer enrollment is deferred by the user. APNs credentials, matching signing/profile entitlements and real suspended-app push delivery remain pending. Do not claim them from synthetic push payload checks.
- A physical iPhone check must establish local-model memory headroom, download reliability, Qwen generation/tool use, thermal behavior and useful sustained context size. Neither 6–8 GiB nor a particular context size is guaranteed by the entitlement template.
- Desktop interaction requires an unlocked Windows session. Browser, file, computation and model work can continue without an interactive desktop. A powered-off or disconnected PC cannot continue executing work.
- Provider inference and account permissions retain ChatGPT-plan preview restrictions. This adds the app's own computer tools; it does not transfer every proprietary Codex/ChatGPT integration into the app.
- Install over the existing app with the same signing identity; preserve all chats, pairings and account data. Inspect actual signing identifiers before any later paid-team migration.

## Evidence before native packaging

- 195 shared-core checks pass on Windows with the synthetic transport fixture.
- Companion protocol/tool/push tests use synthetic providers; no live model request or paid API call was made.
- Actual Edge automation inspected and interacted with an isolated synthetic local page, with screenshot output and stale-reference refusal.
- The actual Docker environment converted a supplied synthetic CSV into a checked workbook and rendered PDF.
- The Windows desktop helper compiled and passed its noninteractive self-check. Real user-desktop interaction is not claimed from this check.

See the final ReleaseValidation110.json and DeviceValidation110.json when available.

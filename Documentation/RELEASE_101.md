# 1.0.1 — one assistant, optional computer tools

Candidate version 1.0.1, build 12. This repairs user-reported 1.0 completion and activity failures and changes ordinary replies to connect directly to the selected ChatGPT account. Physical acceptance is pending.

## Added

- Independent computer tool workspaces: Python, document inspection, selected file input and saved outputs can be used without moving model inference to the PC. Operations keep stable IDs, survive a disconnected phone, and reject conflicting retries.
- Background handoff after an available-PC check. The phone saves its latest work, stops its direct generation before transferring ownership, and continues the same selected model and task on the PC. An already-running computer tool finishes once; its actual receipt and files are carried into the continued task.
- Updating the network address of the same paired PC preserves its device credential and task ownership. This supports moving from LAN to Tailscale without abandoning existing jobs.
- A packaged helper enables silent startup when the user signs in to Windows. A separate administrator helper permits only the companion port on the Tailscale interface.
- Health authorization preflight separates system-rejected types from the rest without reading Health records. Per-type failures remain inspectable; successful selections can be saved.

## Changed

- The computer connection enables optional tools and background work. Everyday text and image questions use the phone's direct ChatGPT connection. No silent model/provider fallback was added.
- The PC's Responses stream adapter now collects completed output items when the terminal response omits them, matching the phone parser. A successful answer is no longer rejected just because the final event has an empty output list. A completion marker is still required before executing any tool.
- The app retains the actual task failure instead of replacing every computer error with a disconnected message. Existing computer jobs reconnect automatically on returning to their chat without consuming the direct-model retry allowance.
- One Live Activity uses native artwork, a state-dependent symbol, elapsed time and up to three observed activity steps. Failed activities dismiss promptly; successful ones stay briefly for return to the chat.
- The compact app orientation describes the mobile assistant, its screens, memory, current connection permissions and optional computer tools. It tells the model to use this orientation directly instead of rediscovering the whole app each chat.
- Home refreshes weather on a five-minute cadence while visible, resumes refresh on foreground return, and retains source/observation attribution.
- Context allowances chosen through the earlier PC route migrate to the corresponding direct-account model preference.

## Removed

- The blanket routing of all ChatGPT responses through the computer.
- The persistent 'via computer' label in the normal chat header.
- The relative 'Checked ... ago' line on Home.
- The 30-minute retention of failed Live Activity cards.

## Validation and remaining limits

All model tests use synthetic streams. The focused SDK regression test exercises the actual OpenAI SSE decoder with completed-item events and empty terminal output; it is not a live inference claim. Native compilation and changed-path tests are recorded separately after the build completes.

Tailscale requires the phone and PC to be signed into the same private network, with the phone VPN enabled. Pairing authorization and existing saved tasks are preserved when changing only the route.

Direct-to-PC handoff requires enough iOS execution time to save and submit it. Abrupt process termination before the PC accepts a job cannot guarantee continuation. Once acknowledged, the PC owns the job independently of the app. Phone-only actions and reviews still require the phone. A PC restart can interrupt an in-flight model connection; saved work remains available, and uncertain actions are not replayed blindly.

Remote APNs Live Activity updates are not provisioned by the current signing route. The activity shows actual received steps while connected and explicitly becomes stale when fresh state cannot be received; it does not animate invented work. PC execution and transcript synchronization do not depend on Live Activity updates. Expansion gestures are controlled by iOS.

Health request preflight does not prove permission to read any particular record and cannot grant clinical entitlements. Physical confirmation of the all-selected authorization flow remains necessary. No personal Health records are collected during development checks.

# Personal Assistant Companion

Computer companion for Personal Assistant 1.0. The iPhone remains the primary interface. This PC process owns long-running work, saves progress independently of the phone connection, and runs supported computation against explicitly supplied files.

The companion uses a separate, user-authorized ChatGPT plan connection on this PC. It does not copy credentials from Codex or the phone and does not configure API billing. Credentials and saved work use an OS-protected key. Phone pairing uses TLS certificate verification and revocable device credentials. Setup stays on the computer's loopback interface.

Computational jobs run with selected inputs, bounded time/memory/output and no task network access. Contacts, Health, location and native communication/planning reviews remain phone operations. A job waiting for the phone or approval keeps that explicit state.

## Open and connect

1. Keep the complete companion package together and open `PersonalAssistant-Computer.exe`. The launcher opens the local setup page after the service is ready.
2. Choose **Continue with ChatGPT** and complete authorization yourself in your browser. This is a separate authorization for this companion, not a copy of the phone or Codex credential.
3. In the setup page choose your Ethernet/Wi-Fi connection and **Show pairing code**. On the iPhone open **Connections → Computer → Scan computer code**.
4. Enable **Use for tools and background work**. Everyday replies use the iPhone direct ChatGPT connection. Computer tools are invoked when useful. Leaving an unfinished reply starts a saved handoff when the PC is available; return to the same chat to catch up. Force-quitting before a handoff is accepted can interrupt that transfer.

The package includes Node. Docker Desktop and Git for Windows/OpenSSL are required on this PC; Docker and the computation image were prepared during development. If the native app cannot reach the PC on private Wi-Fi, the included `scripts/allow-private-wifi.ps1` can be run by the user as administrator. It opens only TCP 48681 for this package's Node executable, on Private networks, from the local subnet. It does not open a public Internet service. Keep setup port 48680 on loopback.

Away-from-home access requires a private route such as Tailscale on both devices. The app connection alone does not configure a VPN. Account sign-in, iPhone pairing and any system access prompts remain user-operated.

The companion requests a temporary Windows system-awake lease while running; it does not keep the display on or alter permanent power settings. Shutting down the PC still stops work. Reopen the companion to retrieve interrupted tasks. Explicit task Stop cancels the saved job; merely closing the phone app disconnects the viewer. Closing the setup browser tab keeps the service running.

## Schedules and files

Ask the assistant to schedule research or a draft while using the Computer connection. One native review shows the exact request, dates and limits. Each schedule has at most 30 runs within 90 days. Each occurrence may research public information and create files from the original input snapshots, for up to ten minutes and twelve tool steps. It cannot send communications or change phone data unattended. Pausing a schedule stops future starts. Results and schedule controls are under **Connections → Computer → Tasks & schedules**. Old missed runs are recorded instead of being launched in a burst.

Python executions have 1.5 GiB memory, two CPU cores and a configurable 1–180 second runtime, with selected read-only inputs and bounded outputs. The environment includes numerical, statistical, spreadsheet, Word, presentation, plotting and PDF libraries. Document inspection distinguishes spreadsheet formulas from cached values and renders actual PDF/Office pages. Office pagination uses LibreOffice and can differ from Microsoft Office. Generated code cannot access the host filesystem, network, credentials or Docker socket.

See the repository's 1.0 release ledger for native and device validation. Sustained remote push/Live Activity updates while iOS fully suspends the app are not provisioned by this free-signing package; the activity labels stale information and refreshes on reconnection. The PC job can continue regardless.

The vendored Sign in with ChatGPT SDK retains its upstream noncommercial license and a modification notice. This package is for the current personal, noncommercial app.

## Startup and a new network route

Run `scripts/enable-startup.ps1` from the package to start silently at Windows sign-in; pass `-Disable` to remove that entry. The browser is a setup page and may be closed. `scripts/allow-tailscale.ps1` requires administrator rights and permits only TCP 48681 for this package on the Tailscale interface.

For a phone that is already paired, choose Connections > Computer > Update network connection and scan a fresh code from the same PC with its Tailscale address selected. The app keeps the existing device credential and saved task ownership. Do not disconnect/re-pair merely to change the address.

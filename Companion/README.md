# Personal Assistant Companion

Computer assistant service for Personal Assistant 1.1. The iPhone remains the primary interface. This PC process owns long-running work, saves progress independently of the phone connection, and runs supported computation against explicitly supplied files.

The companion uses a separate, user-authorized ChatGPT plan connection on this PC. It does not copy credentials from Codex or the phone and does not configure API billing. Credentials and saved work use an OS-protected key. Phone pairing uses TLS certificate verification and revocable device credentials. Setup stays on the computer's loopback interface.

Computational jobs run with selected inputs, bounded time/memory/output and no task network access. Contacts, Health, location and native communication/planning reviews remain phone operations. A job waiting for the phone or approval keeps that explicit state.

## Open and connect

1. Keep the complete companion package together and open `PersonalAssistant-Computer.exe`. The launcher opens the local setup page after the service is ready.
2. Choose **Continue with ChatGPT** and complete authorization yourself in your browser. This is a separate authorization for this companion, not a copy of the phone or Codex credential.
3. In the setup page choose your Ethernet/Wi-Fi connection and **Show pairing code**. On the iPhone open **Connections → Computer → Scan computer code**.
4. Enable **Keep connected tasks on this computer**. Each accepted ChatGPT task belongs to this service from Send. Simple messages go through its lightweight provider connection; computation and computer tools run only when useful. Leaving the app disconnects the viewer without transferring or cancelling the task. A request must finish reaching the PC before it can run independently of the phone.

The package includes Node. Docker Desktop and Git for Windows/OpenSSL are required on this PC; Docker and the computation image were prepared during development. If the native app cannot reach the PC on private Wi-Fi, the included `scripts/allow-private-wifi.ps1` can be run by the user as administrator. It opens only TCP 48681 for this package's Node executable, on Private networks, from the local subnet. It does not open a public Internet service. Keep setup port 48680 on loopback.

Away-from-home access requires a private route such as Tailscale on both devices. The app connection alone does not configure a VPN. Account sign-in, iPhone pairing and any system access prompts remain user-operated.

The companion requests a temporary Windows system-awake lease while running; it does not keep the display on or alter permanent power settings. Shutting down the PC still stops work. Reopen the companion to retrieve interrupted tasks. Explicit task Stop cancels the saved job; merely closing the phone app disconnects the viewer. Closing the setup browser tab keeps the service running.

## Schedules and files

Ask the assistant to schedule research or a draft while using the Computer connection. One native review shows the exact request, dates and limits. Each schedule has at most 30 runs within 90 days. Each occurrence may research public information and create files from the original input snapshots, for up to ten minutes and twelve tool steps. It cannot send communications or change phone data unattended. Pausing a schedule stops future starts. Results and schedule controls are under **Connections → Computer → Tasks & schedules**. Old missed runs are recorded instead of being launched in a burst.

Python executions default to 2 GiB, two CPU cores and 60 seconds, and may request up to 8 GiB, eight cores and 1800 seconds. Inputs remain scoped and read-only; outputs remain bounded. The environment includes numerical, statistical, spreadsheet, Word, presentation, plotting and PDF libraries. Document inspection distinguishes spreadsheet formulas from cached values and renders actual PDF/Office pages. Office pagination uses LibreOffice and can differ from Microsoft Office. Generated code cannot access the host filesystem, network, credentials or Docker socket.

See the repository's release ledger for native and device validation. Direct APNs updates are not provisioned by this free-signing package. The optional PushWard bridge below can deliver status and alerts using its App Store app. The PC job continues independently of notification delivery.

The vendored Sign in with ChatGPT SDK retains its upstream noncommercial license and a modification notice. This package is for the current personal, noncommercial app.

## Startup and a new network route

Run `scripts/enable-startup.ps1` from the package to start silently at Windows sign-in; pass `-Disable` to remove that entry. The browser is a setup page and may be closed. `scripts/allow-tailscale.ps1` requires administrator rights and permits only TCP 48681 for this package on the Tailscale interface.

For a phone that is already paired, choose Connections > Computer > Update network connection and scan a fresh code from the same PC with its Tailscale address selected. The app keeps the existing device credential and saved task ownership. Do not disconnect/re-pair merely to change the address.

## Computer tools and task control

Open a saved task in the control center to follow public progress, review its pending computer action or download a result. Scoped file edits check current content and save a backup before replacement. Host PowerShell and desktop/browser interactions use explicit reviews. Host commands have normal Windows-user access and are not the Docker sandbox. Real desktop interaction requires an unlocked session; the separate Edge browser can run while Windows is locked. No PC-hosted local model streaming is configured.

Apple Developer-dependent notification setup is documented in `Documentation/APPLE_DEVELOPER_SETUP.md` in the source repository. The key is added through the local control center only after matching app provisioning.

## Optional PushWard delivery

Current status (October 13, r4): deferred at Jacob's request. The installed service disconnects any previously enabled bridge and refuses new configure/test requests; the control center hides these controls. The integration key was cleared and existing bridge cards were ended. The implementation details below are retained for historical reference. Native APNs setup remains available for later Apple Developer provisioning.

The control center can connect a PushWard integration key with Activities: Manage and Notifications: Send, optionally restricted to `pa-*`. It stores the key in the existing Windows-protected vault. Only fixed task status and a chat link are sent; prompts, answers, screenshots, documents and Health data are excluded.

The status layout uses a phase icon and label without a fabricated percentage. Use **Open chat** on a Live Activity, or press and hold an alert and choose **Open chat**. A normal notification-body tap opens PushWard's detail screen. PushWard may also confirm a link according to its link settings. Its available templates do not expose a custom looping spinner.

Opening an active task preserves its activity; the updated iPhone app acknowledges a completed task when opened through its link or completed while visible. Ready cards then dismiss immediately. Test cards are separate and clear after two minutes, or with **Clear test activity**. iOS lifetime and provider delivery limits still apply. Economy mode permits four routine phase updates per task and prioritizes attention/completion within the free allowances of 250 activity updates and 500 notifications per UTC month. No plan upgrade or purchase is automatic.

Updates may reuse a byte-identical Node executable that already has the private Tailscale firewall rule. The launcher checks its hash before use; retain prior packages. This avoids changing an existing firewall rule when only app code changes.

The companion's persistent data lives at `%USERPROFILE%\.personal-assistant\computer`, independently of Windows AppData virtualization. On upgrade it preserves an existing legacy store, including one redirected into Codex's MSIX cache, by copying its opaque account/certificate files and taking a consistent SQLite backup. Original files remain untouched. Multiple different populated stores require an explicit recovery choice; the app never silently merges them. Operational launch/update reports are in `%USERPROFILE%\.personal-assistant\logs`.

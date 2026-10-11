# Personal Assistant Companion

Development component for Personal Assistant 1.0. The iPhone remains the primary interface. This PC process owns long-running work, saves progress independently of the phone connection, and runs supported computation against explicitly supplied files.

The companion uses a separate, user-authorized ChatGPT plan connection on this PC. It does not copy credentials from Codex or the phone and does not configure API billing. Credentials and saved work use an OS-protected key. Phone pairing uses TLS certificate verification and revocable device credentials. Setup stays on the computer's loopback interface.

Computational jobs run with selected inputs, bounded time/memory/output and no task network access. Contacts, Health, location and native communication/planning reviews remain phone operations. A job waiting for the phone or approval keeps that explicit state.

This is source under development, not yet a verified installation. See the repository's 1.0 release ledger for implementation and remaining evidence.

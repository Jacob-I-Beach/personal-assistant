# Personal Assistant adaptation

Upstream: OpenAI's Sign in with ChatGPT DevKit, `packages/local`, commit `0a36fefeb913055c8c7a1a29b63d82b96b2e841a`.

This component retains its upstream noncommercial license. Personal Assistant is Jacob's personal, noncommercial application. Independently authored companion code communicates with the component through its interface.

Local changes for 1.0: standalone build configuration and a structured Responses streaming entry point for tool-capable tasks. OAuth, registration, identity verification, scope checks, protected credential storage, profile locking and refresh remain based on the upstream implementation. No credential is exposed to the phone or browser interface. Dependency versions are recorded by the companion lockfile.

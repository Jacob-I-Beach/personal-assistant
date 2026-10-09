# Project guidance

- This is Jacob's private iPhone/iOS 27 application, with an eventual Apple Watch companion. No public-product, billing, or marketplace work is in scope.
- Keep the native app as the real product. Do not build a second Windows phone UI. Windows work must test shared logic, providers, or replay actual captures.
- The app owns conversations, source observations, permissions, and tool execution. Local and connected models use the same core contracts.
- Credentials belong in Keychain or an explicitly supplied process environment. Never put them in Git, logs, messages, test fixtures, or generated tool context.
- Keep tools scoped to explicit user data. Never execute partially streamed or rejected tool calls. Distinguish sensor measurements, OCR, inference, and remembered observations.
- Run `powershell -File scripts/Test-Core.ps1 -Integration` for shared-core changes on Windows. This uses synthetic localhost fixtures, not a paid model API.
- A syntax parse is not an iOS compile. Run the Xcode 27 validation workflow or the README's Mac build command for native changes when Mac access is available.
- Physical camera, depth, memory, and performance claims require a test on the actual phone. Update STATUS.md with evidence and unresolved limits.
- Model weights and personal captures are runtime data, not repository files. Tests use synthetic content.
- Jacob has reported that the first private app opens on his phone. Preserve that working installation and its data; distinguish launch evidence from untested inference and sensor behavior.
- Use `Documentation/PRODUCT_DESIGN.md` as the working proposal for the next substantial milestone. Jacob wants design discussion and coherent release batches, not repeated small device updates. Internal tests and source iterations can remain incremental.
- Model-file import and Apple Foundation Models are priority design questions. Do not call the Apple model the complete Siri assistant or assume access to Private Cloud Compute without its entitlement.

# 1.1.6 — explicit context targets and audit follow-through

Candidate version 1.1.6, build 21. Physical installation and the Apple-granted memory allowance are separate acceptance steps. Health and remote task presentation remain deferred.

## Added

- Qwen 3.5 4B automatic 65,536-token target with native, 8-bit or 4-bit attention-cache selection, using the highest precision estimated to fit. Downloaded model weights are unchanged.
- Audit integration checks through the actual loopback server, persisted database reopen and actual Edge DOM. Concurrent native admission, protected project receipts, interaction rollback, orphan-history migration and the idle/interruption boundary have additional core coverage.

## Changed

- A chosen local context no longer silently shrinks. At the reported 3.05 GiB headroom, Qwen's automatic 64K target is explicitly unavailable; a manually selected 32K context still fits the planning estimate. The 6 GiB fixture plans 64K with native cache precision. These are estimates, not physical measurements or an entitlement grant.
- Engine ownership now includes interruption persistence. A controlled test observed the old idle notification before the saved interruption in all 30 trials; the revised implementation completes that checkpoint before releasing idle waiters.
- Project tool receipts retain classification inherited from linked protected outputs. The previous record itself was protected, but its receipt could omit those flags.
- Browser acquisition is shared for concurrent first requests. Partial acquisition failures close the browser, cancellation is checked between acquisition stages, and shutdown waits for acquired resources.

## Removed

- Forced four-bit attention cache for every Qwen 4B request, even when native precision fits.
- Silent context downgrade and the idle-before-final-checkpoint window.

## Still pending

- Apple profile verification, preservation by the final signer, installation and measured on-phone memory/context behavior. The regular memory entitlement is requested separately from Health, push and debugging-memory capabilities. A local profile helper is prepared; it is not a confirmed grant.
- GPT service recovery: fresh authenticated model-list requests still return HTTP 520 while the anonymous control returns 401. No client cookies, redirect following or connection reuse were needed to reproduce it. Token/header shape checks pass; they cannot establish every upstream account/grant condition. No credentials were erased and no live inference was used.
- Physical sustained 64K input, answer quality, performance and thermal measurements. A larger context estimate does not establish reliable reasoning across every token. Apple Foundation Models retains Apple's own context limit.

See AUDIT_116.md for the complete supplied-audit reconciliation and evidence limits. Native validation results are recorded separately after the workflow completes.

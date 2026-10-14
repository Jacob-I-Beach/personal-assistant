# 1.1.4 — request budgets and model-service coherence

Version 1.1.4, build 19 is packaged for an in-place iPhone update. Computer 1.1.4 release r2 is installed with the account, one paired phone, 23 saved tasks and Windows startup preserved. The phone archive is from `acd2d353c3e2707a3f5657e3a7ed3ebf14c40a8c` / run `38507610419`. See AUDIT_114.md for root-cause evidence and ReleaseValidation114.json for the exact checks. Phone installation remains user-operated.

## Added

- Account-scoped saved model catalogs, freshness/error states, a model-connection check on the PC, and an exact saved-tool-result reader.
- Production request tests using Apple's actual on-device budget, bounded native result tests and a context rollover test that verifies no repeated side effect.

## Changed

- AFM receives concise app/task guidance and loads capability details when relevant. It keeps the full saved chat while working within its real context.
- All prompt components count toward the working budget; the native Apple adapter additionally checks its tokenizer before inference. Large native results are paged, and completed receipts survive a new SDK session.
- Model pickers preserve the selected model, show failures where the choices live, and distinguish saved choices from current availability.
- Model choices come first in the picker. Cellular-download controls live with downloaded models, and the introductory filler is removed.
- Background settings now describe the iPhone time allowance accurately; changing that setting does not stop computer-owned tasks. The paused build no longer suggests using an unavailable system-activity Stop control.
- Saved GPT cards under a local selection explain which model owns the earlier task and expose a useful next action.
- Docker readiness is checked separately, so a slow Python service does not stall account, model-list or saved-task status.

## Removed

- Unrelated tool suggestions when discovery has no matches.
- Silent replacement of an existing model choice after a catalog refresh.
- The misleading “choose more context” preflight failure caused by oversized app instructions, and the higher-budget local UI fixture that failed to catch it.

## Still pending

- The authenticated ChatGPT model service returned HTTP 520 during this audit. The documented endpoint was verified; preserved sign-in is not proof that this upstream failure is resolved. No account-specific model choices are fabricated.
- Physical iPhone installation, AFM inference and long-running acceptance. Health and task notifications/Live Activities remain deferred until developer setup.

## Validation

- 209 shared-core tests passed on Windows and macOS. The former fresh-AFM preflight failure was reproduced first; the corrected production request, memory/attachment budget and receipt-preserving rollover pass.
- 46 companion tests and seven updater checks pass. Synthetic Edge UI checks cover failed model discovery, retained choices and deferred notifications. A real Docker workflow verifies assistant.publish, authorized CSV input, continued state, checked spreadsheet formulas and rendered PDF inspection.
- Full native audit run 38505606747 passed 18 platform tests and four UI scenarios. Only the model-picker layout and background-setting wording changed afterward; final run 38507610419 compiled/archive-validated those changes and passed both affected UI flows. Captured screens were visually inspected.
- Standard IPA: ARM64 iOS device, Metal library present, no requested entitlements, Health disabled, push environment disabled, activity extension retained. SHA-256: `6e494a93c10ff9ba3364b3775302be4bf6da53cdefca56561ac60b582ed7d6e6`.
- No agent live-model inference, new API billing, reauthentication, pairing reset or bridge reconnection. Authenticated model discovery remains HTTP520; cached choices do not prove current inference availability.

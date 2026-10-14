# 1.1.4 — request budgets and model-service coherence

Version 1.1.4, build 19. Implementation is under validation; this file does not yet establish an installed phone update. See AUDIT_114.md for root-cause evidence and scope.

## Added

- Account-scoped saved model catalogs, freshness/error states, a model-connection check on the PC, and an exact saved-tool-result reader.
- Production request tests using Apple's actual on-device budget, bounded native result tests and a context rollover test that verifies no repeated side effect.

## Changed

- AFM receives concise app/task guidance and loads capability details when relevant. It keeps the full saved chat while working within its real context.
- All prompt components count toward the working budget; the native Apple adapter additionally checks its tokenizer before inference. Large native results are paged, and completed receipts survive a new SDK session.
- Model pickers preserve the selected model, show failures where the choices live, and distinguish saved choices from current availability.
- Saved GPT cards under a local selection explain which model owns the earlier task and expose a useful next action.
- Docker readiness is checked separately, so a slow Python service does not stall account, model-list or saved-task status.

## Removed

- Unrelated tool suggestions when discovery has no matches.
- Silent replacement of an existing model choice after a catalog refresh.
- The misleading “choose more context” preflight failure caused by oversized app instructions, and the higher-budget local UI fixture that failed to catch it.

## Still pending

- The authenticated ChatGPT model service returned HTTP 520 during this audit. The documented endpoint was verified; preserved sign-in is not proof that this upstream failure is resolved. No account-specific model choices are fabricated.
- Physical iPhone installation, AFM inference and long-running acceptance. Health and task notifications/Live Activities remain deferred until developer setup.

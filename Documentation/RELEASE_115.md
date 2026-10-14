# 1.1.5 — local runtime readiness and model selection

Version 1.1.5, build 20 is a source candidate. Native compilation, screen review, archive verification and physical-phone acceptance must be recorded separately before calling it delivered.

## Added

- A language-only runtime cache for the already-downloaded, pinned Qwen 3.5 4B checkpoint. It copies the original language tensor bytes in bounded chunks, keeps the original package for vision, and needs approximately 2.37 GB of additional storage on first use. No new model download or altered quantization is involved.
- Runtime preparation before request/context assembly, and tests that distinguish resource readiness from a genuinely oversized request.
- Separate model details, downloads, and account/connection views. Memory details remain available without filling the everyday chooser.

## Changed

- Text-only Qwen requests use its language-model factory. Image requests explicitly require the larger vision runtime; images are not silently dropped or routed to another provider.
- The local planner uses verified text weight bytes and measured process growth after loading, including CPU allocations. It recalculates the fitting context after loading and keeps the requested memory limit as a ceiling rather than a claimed iOS grant.
- Model replacement waits for the previous runtime to become idle and release its allocations. Text prefill and the unused GPU cache are bounded more tightly.
- The model sheet uses concise selectable rows. Saved GPT IDs get readable names without inventing current model availability. Full connection errors are under Manage; download/network and memory controls have their own views.
- Selecting Automatic context now explicitly clears a prior manual context request.

## Removed

- Loading the unused vision tower during text-only Qwen initialization, including the eager-load peak before the upstream sanitizer discarded it.
- The misleading tool/context error emitted before discovering that a local model could not fit in memory.
- Zero-context readouts and diagnostic paragraphs in the everyday model chooser. A runtime that cannot fit is described as a memory-readiness issue.

## Evidence and limits

The reported 3.05 GiB of available headroom became a 2.55 GiB working budget under the old 512 MiB reserve, while the old model charge included 3,034,300,695 bytes of multimodal weights plus 896 MiB. It necessarily produced zero usable context. An 8 GiB preference cannot increase the allowance provided by iOS.

The pinned checkpoint `mlx-community/Qwen3.5-4B-4bit@0e7ffd5c629ef7719d4cbc04069232580bfa9d9c` has 2,367,118,848 bytes of language tensors and 667,028,480 bytes of vision tensors. Its small safetensors header was inspected without downloading or running the model on the PC. MLX Swift LM 3.32.3 supports its text architecture, but Load.swift materializes tensors before sanitation, which is why a real text-only cache is required. The tokenizer, model configuration, language weights and four-bit quantization remain unchanged.

The revised cold planner estimates a 32,768-token text context at 3.05 GiB headroom. This is not physical inference acceptance: actual loaded footprint, tokenizer allocations, thermal state, memory pressure and sustained context performance must still be checked on the phone. The initial reserves are planning allowances and are replaced by measured loaded usage where available. Vision can still exceed the current allowance. No increased-memory entitlement is claimed in the Standard package.

The user confirms AFM now works and the Qwen download completed. Authenticated GPT model discovery still returns HTTP 520; existing token metadata and registered-client binding checks did not reveal a mismatch. One controlled same-account reconnect was requested separately. Saved credentials are not proof of service availability, and this release does not claim to restore GPT.

## Validation

- 217 shared-core tests pass on Windows, including bounded exact-byte weight projection, cache reuse, invalid/truncated inputs, cancellation, measured memory budgets and preparation before context assembly.
- Native platform/UI checks and the unsigned Standard package are pending.
- Health and task notifications/Live Activities remain deferred. No live model inference, new API billing, account reset or pairing reset was performed for validation.

## Primary implementation references

- [Pinned model package](https://huggingface.co/mlx-community/Qwen3.5-4B-4bit/tree/0e7ffd5c629ef7719d4cbc04069232580bfa9d9c)
- [Qwen 3.5 text implementation](https://github.com/ml-explore/mlx-swift-lm/blob/3.32.3/Libraries/MLXLLM/Models/Qwen35.swift)
- [MLX loader materialization](https://github.com/ml-explore/mlx-swift-lm/blob/3.32.3/Libraries/MLXLMCommon/Load.swift)
- [Apple increased memory limit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit)

# Operating behavior

The assistant's capability comes from model quality, instructions, context and app-enforced execution together. This guide documents the current contract; it is not an additional giant system prompt.

The shared runtime guide is AssistantInstructions.base. It tells a model to complete useful work, use tools for facts/actions/calculation, give concise public progress for longer tasks, distinguish evidence from inference, and respect failed tool receipts and declined native actions. It never asks for private chain-of-thought. Simple requests can receive a direct answer.

Context is supplied at runtime: current time zone, selected folder instructions, eligible saved memories, selected files/images, and source references for older saved history. External documents and tool results are evidence, not new user instructions or permission. Connected-model retrieval must pass the app's data-sharing checks.

Provider adapters use supported upstream chat templates and tool parsers. Short-context backends receive find_tools/use_tool with the same execution broker underneath. Larger-context backends receive the concrete tools. Model-provider internal reasoning remains opaque; visible progress comes from actual activity events, public text, a validated plan, and saved tool receipts.

## Regression scenarios

- Exact inputs 18.5, 27.25 and 14.75 compute 60.5; save the CSV from the calculated variables.
- A plain JSON return is accepted. A failed script cannot be bypassed by inventing a file or PDF; a successful repaired execution permits continuation.
- A completed tool call survives an empty terminal response output list. No tool executes from unfinished or rejected arguments.
- A blank terminal answer is a visible failure with the user's request preserved.
- Multi-step work can produce a short public plan and inspectable receipts; do not manufacture reasoning or progress.
- Read a selected document, identify extraction limits, and cite the source. A filename alone is not permission to read arbitrary storage.
- Other chats/files remain unavailable unless workspace permissions allow them; remote retrieval excludes protected source chats before leaking titles/snippets.
- Device information reflects the OS at request time. Model fit estimates are not benchmarks.
- Location needs review and platform permission. Calendar/messages require the user's native editor action. Maps/dialer handoff is not evidence that navigation or a call completed.
- A Jupiter circumference task must distinguish assumed radius, actual observations and evidence; research when needed, compute with code, and state what the limited observations cannot establish.

Deterministic checks validate contracts and failure handling. Real model task quality, local model performance, native editor actions and the reported phone stall require separate physical-device evaluations. Do not label mock-provider tests as successful live model behavior.

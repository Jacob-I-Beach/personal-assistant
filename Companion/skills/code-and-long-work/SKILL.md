---
name: code-and-long-work
description: Inspect a repository, make coherent changes, run relevant checks and maintain a long task across context rollover and questions.
---

1. Establish the requested behavior, repository and existing instructions. Obtain the appropriate folder access. Read relevant files with bounded search/ranges; do not load an entire repository into one request.
2. Save the goal, constraints, current findings, exact file/receipt IDs and next steps with update_work_state. For complex work use update_plan. Notes are public work facts, not private reasoning.
3. Make coherent edits with exact hashes or scoped patches. Preserve unrelated changes. Use existing dependencies and tests where appropriate.
4. Execute focused tests with the available runtime. After failure, inspect the actual exit code and bounded error output. Change the approach before repeating an identical failing action. Tests using fixtures are not proof of a live account, physical phone or external delivery.
5. Context rollover is automatic; full prior inputs and receipts remain retrievable. Read the needed source using read_task_context/read_task_output instead of reconstructing it from memory or repeating effects.
6. Verify the final changes and output files. Report what changed, what passed and any pending user decisions. If a review/answer is still outstanding, finish independent work and explain exactly what that decision unblocks.

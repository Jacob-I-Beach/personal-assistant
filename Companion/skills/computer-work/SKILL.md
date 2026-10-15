---
name: computer-work
description: Use scoped computer files, browser, desktop, shell and GPU tools to complete and verify a Windows task.
---

1. Check computer_status when current readiness or hardware matters. A tool definition is a capability, not proof a dependency is running.
2. Prefer file or structured browser tools to coordinate guessing. Connect only the needed folder; task workspace access already exists. Read bounded ranges/search results. Apply version-checked patches and inspect the result.
3. Use computer_browser for website work. Read its observed page state before acting. Use computer_desktop for native UI; inspect its real screenshot and fresh observation_id, including monitor bounds. Never guess the target or bypass a locked session or UAC.
4. Use run_computer_command for installed programs, Git, native Python or GPU tools. It runs as the user's normal Windows account after exact review. Verify paths and outputs. Prefer isolated run_python for ordinary analysis. A GPU being present does not prove CUDA or a particular package is installed.
5. Pending review holds that action only. Work on independent steps, keep dependent steps pending, and do not resubmit the same action under a new ID. A cancelled or skipped review is never consent. Unknown outcomes require inspection before any repeat.
6. Show requested screenshots/files with publish_task_files. A screenshot inspected internally is not yet displayed in chat. Verify application state or resulting files before claiming the task finished.

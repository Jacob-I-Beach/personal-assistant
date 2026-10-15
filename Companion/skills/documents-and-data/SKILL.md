---
name: documents-and-data
description: Analyze authorized files with Python and create verified charts, spreadsheets, PDF, Word or slide deliverables.
---

1. Read list_task_files and inspect_document for actual input identity, structure and page/cell coverage. Use transfer_file_to_computer if a needed phone file is not present. Do not invent file paths or retype a large dataset through the model.
2. Use run_python with explicit file_ids. The environment supplies assistant.files, assistant.input, assistant.publish(value), assistant.save_state(value), /inputs and /outputs. State is explicit through state_file_id; each execution starts fresh. Host files, network and GPU are separate reviewed host capabilities.
3. Inspect types, missing values, units and relevant rows before calculating. Keep output concise; save large tables as files and intermediate state with stable handles. Diagnose the actual traceback before retrying. Do not assume a helper's presence in a different Python environment.
   `assistant.files` is a list of dictionaries: use each entry's `id`, `filename` and `path`. `assistant.save_state` accepts up to 24 MiB of JSON and returns a state-file handle through the tool receipt; pass it as `state_file_id` on the next call. `assistant.publish` is for a concise result up to 256 KiB. Large state is not the response text.
4. Validate results against independent totals, formula checks or representative source rows. Successful execution alone is insufficient.
5. Render and inspect the real generated document using inspect_document. Check text, table overflow, labels, units and page coverage. Revise if needed, then publish_task_files for the user. Explicitly distinguish unrendered pages and unsolved issues.

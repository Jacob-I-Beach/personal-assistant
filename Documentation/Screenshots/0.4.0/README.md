# Native 0.4.0 screenshots

These 27 captures use synthetic fixtures in the iOS 27 iPhone simulator. They are not live model output or personal phone data. App, core, project and dependency contents are identical between the two source commits, as checked in FeatureValidation.json beside the IPA.

**97 shared-core tests, 14 native platform tests, seven interface scenarios across two runs, and the physical iPhone/Watch Release build.** [Final run 38028597942](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38028597942) reran all core/platform tests and the export interface scenario. The other six interface scenarios passed in [run 38027478506](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38027478506); Git object comparisons verify identical App, Sources, project, package manifest and dependency contents. That earlier run failed only its export-dismissal gesture. The final test successfully saved through the native picker and separately verified cancellation. The 97-test shared suite also passed on Windows. No paid model calls or personal captures were used.

The response layout, mathematical rendering, thinking choices, collapsed/expanded sources, Photos picker, connected-folder controls, output list and native export were visually inspected. Cancellation is confirmed by the native test assertion; there is no dedicated post-cancellation capture. This is selected interaction/layout coverage, not a complete accessibility audit or physical-provider verification.

| Capture | Source run |
| --- | --- |
| [Artifact-preview.png](Artifact-preview.png) | 38027478506 |
| [Connected-file.png](Connected-file.png) | 38028597942 |
| [Conversation-rich-content.png](Conversation-rich-content.png) | 38027478506 |
| [File-attachment.png](File-attachment.png) | 38027478506 |
| [File-detail.png](File-detail.png) | 38027478506 |
| [Files-outputs.png](Files-outputs.png) | 38028597942 |
| [Folder-access.png](Folder-access.png) | 38028597942 |
| [History-search.png](History-search.png) | 38027478506 |
| [Library-files.png](Library-files.png) | 38027478506 |
| [Model-library.png](Model-library.png) | 38027478506 |
| [Models-dark-large-text.png](Models-dark-large-text.png) | 38027478506 |
| [Native-export-completed.png](Native-export-completed.png) | 38028597942 |
| [Native-file-export.png](Native-file-export.png) | 38028597942 |
| [PDF-preview.png](PDF-preview.png) | 38027478506 |
| [Photo-library-picker.png](Photo-library-picker.png) | 38027478506 |
| [Response-calculation.png](Response-calculation.png) | 38027478506 |
| [Response-math-and-answer.png](Response-math-and-answer.png) | 38027478506 |
| [Response-progress-and-web.png](Response-progress-and-web.png) | 38027478506 |
| [Response-web-sources.png](Response-web-sources.png) | 38027478506 |
| [Settings.png](Settings.png) | 38027478506 |
| [Sidebar-folders.png](Sidebar-folders.png) | 38027478506 |
| [Sidebar-managed-chats.png](Sidebar-managed-chats.png) | 38027478506 |
| [Sources-collapsed.png](Sources-collapsed.png) | 38027478506 |
| [Sources-expanded.png](Sources-expanded.png) | 38027478506 |
| [Thinking-effort.png](Thinking-effort.png) | 38027478506 |
| [Welcome-dark-large-text.png](Welcome-dark-large-text.png) | 38027478506 |
| [Welcome-light.png](Welcome-light.png) | 38027478506 |

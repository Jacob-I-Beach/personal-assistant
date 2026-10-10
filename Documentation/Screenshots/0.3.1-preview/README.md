# Native 0.3.1 preview

Synthetic UI screenshots from run 38019229700, source ce0ceedd77e81afb30c9165777701037ebec15d6. The native app compiled and all ten platform tests passed, including both native math parser tests. The UI confirmed separate progress paragraphs, no intermediate response controls, and a working expandable web receipt.

This run was not release-ready: one core assertion and one UI assertion exposed missing number grouping on Apple, and another UI test found the code-copy toolbar overridden by the bundled theme. The calculation image shows the earlier, ungrouped numbers. The source repairs make grouping explicit and apply the custom code style inside the bundled theme. A successful repeat native run and physical-device package remain required.

These are simulator captures with synthetic data, not model output or personal screenshots.

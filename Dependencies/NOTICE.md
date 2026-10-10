# Embedded native components

- QuickJS-NG 0.17.0, upstream commit `6d46d07d04041b40f4f49eaa7fdebe44c314c699`, from https://github.com/quickjs-ng/quickjs. MIT license retained in `Sources/CQuickJS/vendor/LICENSE`. Engine C sources and headers are unmodified. The app wrapper excludes the libc/OS modules, native module loader, worker support, and bytecode loading. Upstream documents iOS with limited testing; native validation remains required.
- SQLite 3.54.0 amalgamation, https://sqlite.org/2026/sqlite-amalgamation-3540000.zip. Public-domain dedication is retained in the source header. Published archive SHA3-256 verified as `7b670a62fdfbd672b75fef004cb703c8a3e87d3a5cc7d675b4a08337004a2d93`; observed SHA-256 `68e913b0fe8ec6b4e5f391c594a28872884e80d6cd042a1e50c957be46b5aa4d`. Extension loading is compiled out.

The upstream versions are intentionally pinned. Updating an engine requires repeating execution-limit, isolation, migration, and native-build checks. These components run locally; no hosted execution service has been provisioned.

Native Swift packages added in this milestone:

- JOSESwift 3.0.0, commit `c2664a902e75c0426a1d43132bd4babc6fd173d3`, https://github.com/airsidemobile/JOSESwift. Apache 2.0 license copied into the app's acknowledgments. It verifies JWS signatures and converts published JWK keys using Apple's Security framework.
- MarkdownUI 2.4.1, commit `5f613358148239d0292c0cef674a3c2314737f9e`, https://github.com/gonzalezreal/swift-markdown-ui. MIT license copied into the app's acknowledgments. Block and inline remote-image providers are replaced with non-networking placeholders. Links require an explicit user tap and permit only HTTP/HTTPS.

- Textual 0.5.0, commit `01b51875a5406eefc95f52a058cb059e7bc94dc4`, https://github.com/gonzalezreal/textual. MIT. The chat renderer uses its native structured text, tables, highlighted code and math attachments. Image/emoji attachment loaders are replaced with local placeholders; links allow only user-selected HTTP/HTTPS destinations. MarkdownUI remains for existing plain-text export utilities.
- SwiftUIMath 0.1.0, commit `0b5c2cfaaec8d6193db206f675048eeb5ce95f71`, https://github.com/gonzalezreal/swiftui-math. MIT, including upstream SwiftMath/iosMath notices. Math is typeset on the device with bundled fonts; font licenses remain in the upstream resource bundle.
- ConcurrencyExtras 1.4.1, https://github.com/pointfreeco/swift-concurrency-extras. MIT; exact revision in Package.resolved. Used by Textual. License included in app acknowledgments.

A Windows SwiftPM resolution fixture verified Textual/SwiftUIMath compatibility with the existing SwiftSyntax 603.0.2 constraint. Native compilation and rendering are separate release checks.
- Prism 1.29.0, https://github.com/PrismJS/prism/tree/v1.29.0. MIT; Textual bundles its JavaScript syntax highlighter for local execution. License included in acknowledgments.

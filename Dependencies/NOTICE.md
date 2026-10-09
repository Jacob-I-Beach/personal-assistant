# Embedded native components

- QuickJS-NG 0.17.0, upstream commit `6d46d07d04041b40f4f49eaa7fdebe44c314c699`, from https://github.com/quickjs-ng/quickjs. MIT license retained in `Sources/CQuickJS/vendor/LICENSE`. Engine C sources and headers are unmodified. The app wrapper excludes the libc/OS modules, native module loader, worker support, and bytecode loading. Upstream documents iOS with limited testing; native validation remains required.
- SQLite 3.54.0 amalgamation, https://sqlite.org/2026/sqlite-amalgamation-3540000.zip. Public-domain dedication is retained in the source header. Published archive SHA3-256 verified as `7b670a62fdfbd672b75fef004cb703c8a3e87d3a5cc7d675b4a08337004a2d93`; observed SHA-256 `68e913b0fe8ec6b4e5f391c594a28872884e80d6cd042a1e50c957be46b5aa4d`. Extension loading is compiled out.

The upstream versions are intentionally pinned. Updating an engine requires repeating execution-limit, isolation, migration, and native-build checks. These components run locally; no hosted execution service has been provisioned.

Native Swift packages added in this milestone:

- JOSESwift 3.0.0, commit `c2664a902e75c0426a1d43132bd4babc6fd173d3`, https://github.com/airsidemobile/JOSESwift. Apache 2.0 license copied into the app's acknowledgments. It verifies JWS signatures and converts published JWK keys using Apple's Security framework.
- MarkdownUI 2.4.1, commit `5f613358148239d0292c0cef674a3c2314737f9e`, https://github.com/gonzalezreal/swift-markdown-ui. MIT license copied into the app's acknowledgments. Block and inline remote-image providers are replaced with non-networking placeholders. Links require an explicit user tap and permit only HTTP/HTTPS.

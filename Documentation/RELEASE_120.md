# Personal Assistant 1.2.0 candidate

This batch completes the remaining implementable work from the supplied code and product audits. It is undergoing validation; this document is not a device-acceptance receipt.

- Added: direct project creation and continuation; transcript revision history and explicit restore; a versioned local archive with integrity checks, isolated restore and next-launch library selection; Inbox search, filters, movement and removed-note recovery; model/package/cache removal with an explicit storage boundary.
- Changed: one root presentation owner, read-only browsing while another response runs, source-owned rendering, common readiness and output presentation, exact stepped scenario inputs, accessible image coordinates, source-message links for memory, grouped Settings, indexed Library filters and excerpts, bounded HTTP reception, browser idle/resource limits and shared Swift/JavaScript argument fixtures.
- Removed: the requirement to stop a response just to read another saved chat; destructive transcript truncation without a retained prior version; full re-encoding of unchanged messages at every cached checkpoint; irrelevant zero-overlap global notes in ordinary retrieval.
- Validation pending: native compilation, focused platform and end-to-end UI journeys, visual review and final packaging. Physical installation, real account/model inference, on-phone memory/voice/camera tests and developer provisioning remain separate. Health, APNs and external notification bridges remain disabled.

Archives preserve source identities and revisions, and do not import account credentials, pairing keys, connected-folder permissions or executable work queues. Protected work is an explicit export choice. Restore keeps the existing library and takes effect only after an explicit selection and a later app launch.

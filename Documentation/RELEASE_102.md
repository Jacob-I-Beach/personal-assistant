# 1.0.2 — Tailscale connection repair

Candidate version 1.0.2, build 13. Jacob reported a TLS error when scanning the computer connection code after Tailscale setup. PC-side HTTPS reachability and the existing certificate pin pass; physical iPhone pairing is not yet confirmed.

## Added

- A focused native URLSession regression fixture that reproduces the previous app transport policy at a synthetic Tailscale address, then verifies the repaired policy with the same certificate and client. The certificate is generated on the runner; no device keys, pairing codes, or personal records are used.

## Changed

- The app transport policy permits the companion's existing QR-pinned certificate evaluation on Tailscale's `100.64.0.0/10` address range. Modern iOS requires explicit IP-range exceptions; the previous local-network setting alone did not declare this range.
- The companion still requires HTTPS, an exact SHA-256 certificate match, the expected host, and no redirects. No global arbitrary-load exception, lower TLS version, or weaker cipher setting is introduced.

## Removed

- Nothing from the app's UI or capabilities. This is a connection repair only.

## Still pending

- Native before/after TLS results and package receipt will be recorded after validation.
- Physical scanning over the iPhone's Tailscale connection remains the final acceptance check.

The PC certificate, server identity, device credential, saved jobs, sign-in and Windows startup configuration are preserved. Install over the existing app with the same Apple signing account. Use **Update network connection** for the same PC; do not disconnect the phone's existing pairing merely to change its route.

Apple documents [IP-range exceptions](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAppTransportSecurity/NSExceptionDomains) and the [exception needed for custom HTTPS trust evaluation](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSExceptionAllowsInsecureHTTPLoads). The narrowly scoped exception enables the existing pin check; it does not itself approve a certificate.

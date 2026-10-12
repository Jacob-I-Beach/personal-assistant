# 1.0.2 — Tailscale connection repair

Packaged version 1.0.2, build 13, from source `942b7584119bb0afe3fd48c70858c2d8f2259463` in [run 38199838169](https://github.com/Jacob-I-Beach/personal-assistant/actions/runs/38199838169). Jacob reported a TLS error when scanning the computer connection code after Tailscale setup. The native regression reproduced the exact `NSURLErrorDomain -1200` error under the old policy and connected successfully with the repaired policy. Physical iPhone acceptance is pending.

## Added

- A focused native URLSession regression fixture that reproduces the previous app transport policy at a synthetic Tailscale address, then verifies the repaired policy with the same certificate and client. The certificate is generated on the runner; no device keys, pairing codes, or personal records are used.

## Changed

- The app transport policy permits the companion's existing QR-pinned certificate evaluation on Tailscale's `100.64.0.0/10` address range. Modern iOS requires explicit IP-range exceptions; the previous local-network setting alone did not declare this range.
- The companion still requires HTTPS, an exact SHA-256 certificate match, the expected host, and no redirects. No global arbitrary-load exception, lower TLS version, or weaker cipher setting is introduced.

## Removed

- Nothing from the app's UI or capabilities. This is a connection repair only.

## Still pending

- Physical scanning over the iPhone's Tailscale connection remains the final acceptance check.

## Validation

- The old policy reproduced `ATS failed system trust`, followed by `NSURLErrorDomain -1200`.
- With only the app transport configuration changed, the same native URLSession client connected to the same generated self-signed certificate at a synthetic Tailscale address.
- Five repaired-policy checks passed: pinned Tailscale HTTPS, retained local HTTPS, wrong-certificate rejection before any device token was sent, redirect refusal without credential forwarding, and continued HTTPS-only requests without a global ATS opt-out.
- The physical iPhone archive and 186 shared-core tests passed. No broad UI suite, live model call, personal Health read or real device-token test was needed for this repair.
- The downloaded IPA's checksum, physical ARM64 executable, bundle identity, Health setting, Activity extension and actual packaged ATS policy were verified. See `ReleaseValidation102.json` for provenance.

The PC certificate, server identity, device credential, saved jobs, sign-in and Windows startup configuration are preserved. Install over the existing app with the same Apple signing account. Use **Update network connection** for the same PC; do not disconnect the phone's existing pairing merely to change its route.

Apple documents [IP-range exceptions](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAppTransportSecurity/NSExceptionDomains) and the [exception needed for custom HTTPS trust evaluation](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSExceptionAllowsInsecureHTTPLoads). The narrowly scoped exception enables the existing pin check; it does not itself approve a certificate.

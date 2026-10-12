#!/bin/bash
# Runs actual iOS URLSession requests against a synthetic companion on this runner.
set -euo pipefail
bundle="$1"
simulator_id="$2"
app_plist="DerivedData/Build/Products/Debug-iphonesimulator/PersonalAssistant.app/Info.plist"
cp "$app_plist" .build/companion-repaired.plist
fixture_pid=""
cleanup() {
  cp .build/companion-repaired.plist "$app_plist"
  if [ -n "$fixture_pid" ]; then kill "$fixture_pid" 2>/dev/null || true; fi
  sudo ifconfig lo0 -alias 100.64.0.1 || true
}
trap cleanup EXIT

# A synthetic CGNAT alias exercises the same ATS classification as Tailscale.
sudo ifconfig lo0 alias 100.64.0.1 255.255.255.255
python3 scripts/companion_tls_fixture.py > .build/companion-tls-fixture.log 2>&1 &
fixture_pid=$!
for attempt in $(seq 1 100); do
  if curl --noproxy '*' -fsS http://localhost:48682/config > /dev/null; then break; fi
  kill -0 "$fixture_pid"
  sleep 0.1
done
curl --noproxy '*' -fsS http://localhost:48682/config > /dev/null
python3 - "$bundle" <<'PY'
import plistlib, sys
from pathlib import Path
path = Path(sys.argv[1])
data = plistlib.loads(path.read_bytes())
def configure(value):
    if isinstance(value, dict):
        if "TestBundlePath" in value:
            value.setdefault("EnvironmentVariables", {})["ASSISTANT_TLS_FIXTURE"] = "1"
        for nested in value.values():
            configure(nested)
    elif isinstance(value, list):
        for nested in value:
            configure(nested)
configure(data)
path.write_bytes(plistlib.dumps(data))
PY

# Reproduce build 12's exact networking policy in the synthetic test host first.
/usr/libexec/PlistBuddy -c 'Delete :NSAppTransportSecurity:NSExceptionDomains' "$app_plist"
xcodebuild test-without-building -xctestrun "$bundle" -destination "platform=iOS Simulator,id=$simulator_id" \
  -resultBundlePath .build/TLSLegacy.xcresult -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:PersonalAssistantPlatformTests/CompanionTLSPlatformTests/testLegacyPolicyRejectsTailscaleCertificate \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee .build/tls-legacy-tests.log

# Reinstall the same binary with only the repaired networking policy restored.
cp .build/companion-repaired.plist "$app_plist"
xcrun simctl uninstall "$simulator_id" dev.jacob.personalassistant
xcodebuild test-without-building -xctestrun "$bundle" -destination "platform=iOS Simulator,id=$simulator_id" \
  -resultBundlePath .build/UITests.xcresult -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:PersonalAssistantPlatformTests/CompanionTLSPlatformTests \
  -skip-testing:PersonalAssistantPlatformTests/CompanionTLSPlatformTests/testLegacyPolicyRejectsTailscaleCertificate \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee .build/ui-tests.log

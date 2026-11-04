#!/bin/bash
# Offline iOS Simulator tests with public fixture keys only. Never broadcasts.
set -euo pipefail
xcodegen generate --spec project.yml
simulator_id="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); a=[v for k,vs in d["devices"].items() if "iOS" in k for v in vs if v.get("isAvailable",True) and "iPhone" in v["name"]]; assert a,"No available iPhone simulator"; print(a[0]["udid"])')"
xcodebuild test -project Console.xcodeproj -scheme Console \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -only-testing:ConsoleTests/WalletEVMSigningTests \
  -only-testing:ConsoleTests/WalletUSDTSigningIntegrationTests \
  -only-testing:ConsoleTests/SpyderChatPaymentTests \
  -only-testing:ConsoleTests/WalletRecoveryParityTests \
  CODE_SIGNING_ALLOWED=NO

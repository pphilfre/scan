#!/bin/bash
set -euo pipefail
mkdir -p build
simulator_id="$(python3 scripts/select-simulator.py)"
xcrun simctl boot "$simulator_id" || true
xcrun simctl bootstatus "$simulator_id" -b > build/simulator-boot.log 2>&1 &
boot_pid=$!
# Compile while the existing simulator boots.
xcodebuild -project Folio.xcodeproj -scheme Folio -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" -derivedDataPath build/Simulator \
  -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO \
  build-for-testing 2>&1 | tee build/test-build.log
wait "$boot_pid"
xcodebuild -project Folio.xcodeproj -scheme Folio -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" -derivedDataPath build/Simulator \
  -resultBundlePath build/Tests.xcresult -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test-without-building 2>&1 | tee build/tests.log

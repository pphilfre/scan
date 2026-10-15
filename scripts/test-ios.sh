#!/bin/bash
set -euo pipefail
mkdir -p build
simulator_arch="$(uname -m)"
# Starting CoreSimulator can take minutes on a cold runner. Keep all of its
# discovery and boot commands off the compilation path, not just bootstatus.
(
  simulator_id="$(python3 scripts/select-simulator.py)"
  echo "$simulator_id" > build/simulator-id.txt
  xcrun simctl boot "$simulator_id" || xcrun simctl list devices booted | grep -F "$simulator_id"
  xcrun simctl bootstatus "$simulator_id" -b
) > build/simulator-boot.log 2>&1 &
boot_pid=$!
trap 'kill "$boot_pid" 2>/dev/null || true' EXIT
# A generic destination compiles without waiting for a running simulator.
xcodebuild -project Folio.xcodeproj -scheme Folio -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/Simulator \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  ARCHS="$simulator_arch" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  build-for-testing 2>&1 | tee build/test-build.log
wait "$boot_pid"
trap - EXIT
simulator_id="$(cat build/simulator-id.txt)"
xcodebuild -project Folio.xcodeproj -scheme Folio -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id,arch=$simulator_arch" -derivedDataPath build/Simulator \
  -resultBundlePath build/Tests.xcresult -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test-without-building 2>&1 | tee build/tests.log

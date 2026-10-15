#!/bin/bash
set -euo pipefail
mkdir -p build
xcodebuild -project Folio.xcodeproj -scheme Folio -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/Device \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  build 2>&1 | tee build/device-build.log
app_path=build/Device/Build/Products/Release-iphoneos/Folio.app
test -f "$app_path/Folio"
lipo "$app_path/Folio" -verify_arch arm64
rm -rf build/ipa
mkdir -p build/ipa/Payload
ditto "$app_path" build/ipa/Payload/Folio.app
(cd build/ipa && /usr/bin/zip -qry ../Folio-unsigned.ipa Payload)
unzip -t build/Folio-unsigned.ipa
(cd build && shasum -a 256 Folio-unsigned.ipa > Folio-unsigned.ipa.sha256)

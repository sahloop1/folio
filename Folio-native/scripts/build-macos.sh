#!/bin/bash
set -euo pipefail
folio_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$folio_root"
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null 2>&1; then
    printf '%s\n' 'Native iPad builds require macOS with Xcode. This Linux check does not create an IPA.' >&2
    exit 2
fi
mode="${1:-check}"
mkdir -p build
case "$mode" in
    check)
        python3 scripts/check.py
        swift test --parallel
        folio_simulator="$(python3 scripts/simulator.py)"
        xcodebuild test -project Folio.xcodeproj -scheme Folio -configuration Debug \
            -destination "platform=iOS Simulator,id=$folio_simulator" \
            -derivedDataPath build/DerivedData -resultBundlePath "build/Folio-$(date -u +%Y%m%dT%H%M%SZ).xcresult" \
            -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
        xcodebuild build -project Folio.xcodeproj -scheme Folio -configuration Release \
            -destination 'generic/platform=iOS' -derivedDataPath build/Device CODE_SIGNING_ALLOWED=NO
        printf '%s\n' 'Simulator tests and unsigned device compilation finished. This is not a signed installable app.'
        ;;
    archive)
        : "${FOLIO_TEAM_ID:?Set FOLIO_TEAM_ID to the Apple development team ID.}"
        xcodebuild archive -project Folio.xcodeproj -scheme Folio -configuration Release \
            -destination 'generic/platform=iOS' -archivePath build/Folio.xcarchive \
            -allowProvisioningUpdates "DEVELOPMENT_TEAM=$FOLIO_TEAM_ID"
        printf '%s\n' 'Archive created. Use Xcode Organizer to sign/export or upload to App Store Connect.'
        ;;
    export)
        : "${FOLIO_EXPORT_OPTIONS:?Set FOLIO_EXPORT_OPTIONS to an export-options plist prepared for your signing team.}"
        xcodebuild -exportArchive -archivePath build/Folio.xcarchive \
            -exportOptionsPlist "$FOLIO_EXPORT_OPTIONS" -exportPath build/Signed -allowProvisioningUpdates
        ;;
    *) printf '%s\n' 'Usage: bash scripts/build-macos.sh [check|archive|export]' >&2; exit 2 ;;
esac

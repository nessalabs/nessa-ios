#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
platform=${1:-simulator}
configuration=${2:-Debug}
case "$platform" in
  simulator) sdk=iphonesimulator; destination=ios-simulator; device=() ;;
  device) sdk=iphoneos; destination=ios; device=(--device) ;;
  *) echo "Choose simulator or device" >&2; exit 2 ;;
esac
case "$configuration" in Debug|Release) ;; *) echo "Choose Debug or Release" >&2; exit 2 ;; esac

# Bake the embedded plan for both configurations. NessaFeatures' Xcode configuration
# independently controls development fixtures, and Release always selects live adapters.
export EXACT_APP_DIR="$PWD"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$PWD/target}"
bun exact.mjs ios --embed --no-install --release ${device[@]+"${device[@]}"}
embed=$(bun -e 'import { appleArtifacts } from "../Vendor/Exact/host/apple/build.mjs"; import { resolveApp } from "../Vendor/Exact/scripts/app.mjs"; console.log(appleArtifacts(resolveApp("nessa-apple"), {destination:process.argv[1], trust:"production"}).embed)' "$destination")
export EXACT_LIB_DIR="$embed" EXACT_LIB=nessa_apple EXACT_UPDATE_TRUST=production EXACT_APPLE_LINK=grouped_lists,markdown
bun tools/prepare-module.mjs
xcodegen generate --spec Apple/project.yml
xcodebuild -project Apple/NessaExact.xcodeproj -scheme Nessa -configuration "$configuration" \
  -sdk "$sdk" -destination "generic/platform=$(if [[ $sdk == iphoneos ]]; then echo iOS; else echo 'iOS Simulator'; fi)" \
  -derivedDataPath "${NESSA_DERIVED_DATA:-$PWD/.exact/xcode}" \
  "LIBRARY_SEARCH_PATHS=\$(inherited) \"$embed\"" ARCHS=arm64 "${@:3}" "${NESSA_BUILD_ACTION:-build}"

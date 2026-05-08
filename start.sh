#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$ROOT/App/Clawdia.xcodeproj"
SCHEME="Clawdia"
APP_BUNDLE_ID="com.clawdia.mobile"

find_xcode_developer_dir() {
  local candidates=()

  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    candidates+=("$DEVELOPER_DIR")
  fi

  candidates+=(
    "$(xcode-select -p 2>/dev/null || true)"
    "/Applications/Xcode.app/Contents/Developer"
    "/Applications/Xcode-beta.app/Contents/Developer"
    "$HOME/Applications/Xcode.app/Contents/Developer"
    "$HOME/Applications/Xcode-beta.app/Contents/Developer"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate/usr/bin/xcodebuild" && -x "$candidate/usr/bin/simctl" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

if ! developer_dir="$(find_xcode_developer_dir)"; then
  cat >&2 <<EOF
Full Xcode with iOS Simulator support is required to build and launch this app.

Current developer directory:
  $(xcode-select -p 2>/dev/null || echo "not set")

I could not find Xcode in:
  /Applications/Xcode.app
  /Applications/Xcode-beta.app
  ~/Applications/Xcode.app
  ~/Applications/Xcode-beta.app

Install Xcode from the App Store or Apple Developer, open it once, then rerun:
  ./start.sh

This script uses Xcode through DEVELOPER_DIR and does not require changing global xcode-select.
EOF
  exit 1
fi

export DEVELOPER_DIR="$developer_dir"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required but was not found." >&2
  exit 1
fi

if ! xcrun simctl list devices available >/dev/null 2>&1; then
  echo "simctl is unavailable through DEVELOPER_DIR=$DEVELOPER_DIR." >&2
  exit 1
fi

destination_id="$(
  xcrun simctl list devices available |
    awk -F '[()]' '/iPhone/ && /Booted/ { print $2; exit }'
)"

if [[ -z "$destination_id" ]]; then
  destination_id="$(
    xcrun simctl list devices available |
      awk -F '[()]' '/iPhone/ && /Shutdown/ { print $2; exit }'
  )"
fi

if [[ -z "$destination_id" ]]; then
  echo "No available iPhone simulator was found." >&2
  exit 1
fi

xcrun simctl boot "$destination_id" >/dev/null 2>&1 || true
open "$DEVELOPER_DIR/Applications/Simulator.app"
xcrun simctl bootstatus "$destination_id" -b

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -resolvePackageDependencies

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "id=$destination_id" \
  -configuration Debug \
  -derivedDataPath "$ROOT/DerivedData" \
  build

app_path="$(
  find "$ROOT/DerivedData/Build/Products/Debug-iphonesimulator" \
    -maxdepth 1 \
    -name "$SCHEME.app" \
    -type d \
    -print \
    -quit
)"

if [[ -z "$app_path" ]]; then
  echo "Built app was not found under DerivedData." >&2
  exit 1
fi

xcrun simctl install "$destination_id" "$app_path"
xcrun simctl launch "$destination_id" "$APP_BUNDLE_ID"

echo "Launched $SCHEME on simulator $destination_id"

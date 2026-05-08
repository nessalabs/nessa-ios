#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$ROOT/App/Clawdia.xcodeproj"
SCHEME="Clawdia"
APP_BUNDLE_ID="com.clawdia.mobile"
DERIVED_DATA="$ROOT/DerivedData-iPhone"

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
    if [[ -x "$candidate/usr/bin/xcodebuild" && -x "$candidate/usr/bin/devicectl" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

json_extract() {
  local file="$1"
  local key="$2"
  plutil -extract "$key" raw -o - "$file" 2>/dev/null || true
}

project_team_id() {
  awk -F '= ' '/DEVELOPMENT_TEAM = [A-Z0-9]+;/ {
    gsub(/;/, "", $2)
    print $2
    exit
  }' "$PROJECT/project.pbxproj"
}

if ! developer_dir="$(find_xcode_developer_dir)"; then
  cat >&2 <<EOF
Full Xcode with iPhone device support is required.

Install Xcode, open it once, then rerun:
  ./iphone.sh
EOF
  exit 1
fi

export DEVELOPER_DIR="$developer_dir"

devices_json="$(mktemp)"
trap 'rm -f "$devices_json"' EXIT

if ! xcrun devicectl list devices --json-output "$devices_json" >/dev/null; then
  echo "Could not list connected iPhones through devicectl." >&2
  exit 1
fi

device_udid="${IPHONE_UDID:-$(json_extract "$devices_json" "result.devices.0.hardwareProperties.udid")}"
device_name="$(json_extract "$devices_json" "result.devices.0.deviceProperties.name")"
developer_mode="$(json_extract "$devices_json" "result.devices.0.deviceProperties.developerModeStatus")"
ddi_available="$(json_extract "$devices_json" "result.devices.0.deviceProperties.ddiServicesAvailable")"

if [[ -z "$device_udid" ]]; then
  cat >&2 <<EOF
No connected iPhone was found.

Connect your iPhone with USB, unlock it, tap Trust This Computer, then rerun:
  ./iphone.sh
EOF
  exit 1
fi

if [[ "$developer_mode" != "enabled" ]]; then
  cat >&2 <<EOF
Connected iPhone "${device_name:-$device_udid}" is not ready for local app installs.

On the iPhone:
  1. Open Settings > Privacy & Security > Developer Mode.
  2. Turn Developer Mode on.
  3. Restart when iOS asks.
  4. Unlock the phone and trust this Mac.

Current Developer Mode status: ${developer_mode:-unknown}
Current Developer Disk Image services: ${ddi_available:-unknown}

Then rerun:
  ./iphone.sh
EOF
  exit 1
fi

team_id="${DEVELOPMENT_TEAM:-${APPLE_TEAM_ID:-$(project_team_id)}}"
build_settings=(
  CODE_SIGN_STYLE=Automatic
)

if [[ -n "$team_id" ]]; then
  build_settings+=("DEVELOPMENT_TEAM=$team_id")
fi

echo "Building $SCHEME for ${device_name:-$device_udid}..."
if ! xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "id=$device_udid" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  "${build_settings[@]}" \
  build; then
  if [[ -z "$team_id" ]]; then
    cat >&2 <<EOF

Build failed and no Apple development team is configured.

Run with your Apple team id:
  DEVELOPMENT_TEAM=YOURTEAMID ./iphone.sh

You can find the team id in Xcode:
  Xcode > Settings > Accounts > your Apple ID > Team > Team ID
EOF
  fi
  exit 1
fi

app_path="$(
  find "$DERIVED_DATA/Build/Products/Debug-iphoneos" \
    -maxdepth 1 \
    -name "$SCHEME.app" \
    -type d \
    -print \
    -quit
)"

if [[ -z "$app_path" ]]; then
  echo "Built app was not found under $DERIVED_DATA/Build/Products/Debug-iphoneos." >&2
  exit 1
fi

echo "Installing $app_path on ${device_name:-$device_udid}..."
xcrun devicectl device install app --device "$device_udid" "$app_path"

echo "Launching $APP_BUNDLE_ID..."
xcrun devicectl device process launch --device "$device_udid" --terminate-existing "$APP_BUNDLE_ID" || true

echo "Installed $SCHEME on ${device_name:-$device_udid}."

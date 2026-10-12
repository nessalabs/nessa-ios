#!/bin/sh
# Wrap one frozen gateway build in a self-contained Apple Swift package.
# Requires the gateway's Rust toolchain/Apple targets, Xcode, Swift and Python 3.
set -eu
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 GATEWAY_CHECKOUT COMMIT FRESH_OUTPUT_DIRECTORY" >&2
  exit 1
fi
gateway=$(CDPATH= cd -- "$1" && pwd)
revision=$(git -C "$gateway" rev-parse --verify "$2^{commit}")
frozen() {
  current=$(git -C "$gateway" rev-parse HEAD) || return 1
  changes=$(git -C "$gateway" status --porcelain) || return 1
  [ "$current" = "$revision" ] && [ -z "$changes" ]
}
if ! frozen; then
  echo "Gateway checkout must be clean and checked out at the specified commit." >&2
  exit 1
fi
output=$3
if [ -e "$output" ] || [ -L "$output" ]; then
  echo "Choose a fresh output directory; the existing package is preserved." >&2
  exit 1
fi
mkdir -p "$(dirname -- "$output")"
parent=$(CDPATH= cd -- "$(dirname -- "$output")" && pwd)
output="$parent/$(basename -- "$output")"
scratch=$(mktemp -d "$parent/.native-package.XXXXXXXX")
trap 'rm -rf "$scratch"' EXIT
trap 'exit 1' HUP INT TERM
build=${CARGO_TARGET_DIR:-"$gateway/target"}
mkdir -p "$build"
build=$(CDPATH= cd -- "$build" && pwd)
export CARGO_TARGET_DIR="$build"
"$gateway/scripts/build-native-device.sh" "$scratch/generated"

# Generation and compilation remain gateway-owned. Only bundle layout changes.
name=nessa_device_clientFFI
package="$scratch/package"
mkdir -p "$package/Sources"
cp "$scratch/generated/Sources/"*.swift "$package/Sources/"
for platform in ios simulator macos; do
  case "$platform" in
    ios) library="$build/aarch64-apple-ios/release/libnessa_device_client.dylib"; minimum=18.0; supported=iPhoneOS ;;
    simulator) library="$build/aarch64-apple-ios-sim/release/libnessa_device_client.dylib"; minimum=18.0; supported=iPhoneSimulator ;;
    macos) library="$build/release/libnessa_device_client.dylib"; minimum=15.0; supported=MacOSX ;;
  esac
  framework="$scratch/$platform/$name.framework"
  if [ "$platform" = macos ]; then
    content="$framework/Versions/A"
    mkdir -p "$content/Resources"
    ln -s A "$framework/Versions/Current"
    for item in "$name" Headers Modules Resources; do
      ln -s "Versions/Current/$item" "$framework/$item"
    done
    plist="$content/Resources/Info.plist"
  else
    content="$framework"
    plist="$framework/Info.plist"
  fi
  mkdir -p "$content/Headers" "$content/Modules"
  cp "$library" "$content/$name"
  cp "$scratch/generated/Headers/$name.h" "$content/Headers/"
  # Clang framework modules use the same generated ABI/header identity.
  sed 's/^module /framework module /' \
    "$scratch/generated/Headers/module.modulemap" > "$content/Modules/module.modulemap"
  /usr/libexec/PlistBuddy -c 'Clear dict' "$plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $name" "$plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string app.nessa.native-device' "$plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string FMWK' "$plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.1.0' "$plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "$plist"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleSupportedPlatforms array' "$plist"
  /usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms:0 string $supported" "$plist"
  if [ "$platform" = macos ]; then
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $minimum" "$plist"
  else
    /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string $minimum" "$plist"
  fi
  install_name_tool -id "@rpath/$name.framework/$name" "$content/$name"
  codesign --force --sign - --timestamp=none "$framework"
done
xcodebuild -create-xcframework \
  -framework "$scratch/ios/$name.framework" \
  -framework "$scratch/simulator/$name.framework" \
  -framework "$scratch/macos/$name.framework" \
  -output "$package/NessaDeviceClient.xcframework"
cat > "$package/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NessaNative",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "NessaNative", targets: ["NessaNative"])],
    targets: [
        .binaryTarget(name: "nessa_device_clientFFI", path: "NessaDeviceClient.xcframework"),
        .target(name: "NessaNative", dependencies: ["nessa_device_clientFFI"], path: "Sources")
    ]
)
SWIFT
if [ -f "$gateway/LICENSE" ]; then cp "$gateway/LICENSE" "$package/LICENSE"; fi
if ! frozen; then
  echo "Gateway source changed during compilation; no package was published." >&2
  exit 1
fi
python3 - "$gateway" "$revision" "$package" <<'PY'
import hashlib, json, os, pathlib, sys
gateway, revision, package = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
files = {str(p.relative_to(package)): digest(p) for p in sorted(package.rglob('*'))
         if p.is_file() and not p.is_symlink()}
symlinks = {str(p.relative_to(package)): os.readlink(p) for p in sorted(package.rglob('*'))
            if p.is_symlink()}
(package / 'SOURCE.json').write_text(json.dumps({
    'repository': 'https://github.com/nessalabs/nessa-agent',
    'commit': revision, 'cargoLockSHA256': digest(gateway / 'Cargo.lock'),
    'module': 'nessa_device_clientFFI', 'architectures': ['arm64'],
    'files': files, 'symlinks': symlinks,
}, indent=2, sort_keys=True) + '\n')
PY
python3 "$(dirname -- "$0")/publish-native-package.py" "$package" "$output"
echo "Native package: $output (gateway $revision)"

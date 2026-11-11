#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG="$(command -v rg)" || { echo "Verifier regression tests require ripgrep (rg)." >&2; exit 1; }
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/scripts" "$TEMP/bin" "$TEMP/Sources/NessaFeatures/"{Domain,Application,Presentation}
cp "$ROOT/scripts/verify_architecture.sh" "$TEMP/scripts/"
ln -s "$(command -v dirname)" "$TEMP/bin/dirname"
for layer in Domain Application Presentation; do
  printf 'import Foundation\n' > "$TEMP/Sources/NessaFeatures/$layer/Fixture.swift"
done

expect_result() {
  local expected="$1" message="$2" status=0
  PATH="$TEMP/bin" /bin/bash "$TEMP/scripts/verify_architecture.sh" > "$TEMP/output" 2>&1 || status=$?
  if [[ "$status" -ne "$expected" ]] || ! grep -Fq "$message" "$TEMP/output"; then
    cat "$TEMP/output" >&2
    echo "Expected exit $expected and '$message'; got exit $status." >&2
    exit 1
  fi
  if [[ "$expected" -ne 0 ]] && grep -Fq 'Architecture verifier passed' "$TEMP/output"; then
    echo "Failed verifier reported success." >&2
    exit 1
  fi
}

expect_result 1 'requires ripgrep'
cat > "$TEMP/bin/rg" <<'RG'
#!/bin/sh
exit 2
RG
chmod +x "$TEMP/bin/rg"
expect_result 1 'rg exit 2'
# A later scan must also fail closed after all import scans return no match.
cat > "$TEMP/bin/rg" <<'RG'
#!/bin/sh
case "$3" in
  */Presentation) exit 2 ;;
  *) exit 1 ;;
esac
RG
expect_result 1 'could not scan Sources/NessaFeatures/Presentation'
rm "$TEMP/bin/rg"
ln -s "$RG" "$TEMP/bin/rg"
expect_result 0 'Architecture verifier passed'
printf 'import SwiftUI\n' > "$TEMP/Sources/NessaFeatures/Domain/Fixture.swift"
expect_result 1 'Domain must not import SwiftUI'
printf 'import Foundation\n' > "$TEMP/Sources/NessaFeatures/Domain/Fixture.swift"
printf 'import UIKit\n' > "$TEMP/Sources/NessaFeatures/Application/Fixture.swift"
expect_result 1 'Application must not import UIKit'
printf 'import Foundation\n' > "$TEMP/Sources/NessaFeatures/Application/Fixture.swift"
printf 'let client = NessaGatewayClient()\n' > "$TEMP/Sources/NessaFeatures/Presentation/Fixture.swift"
expect_result 1 'presentation must receive adapters through composition'
printf 'import Foundation\n' > "$TEMP/Sources/NessaFeatures/Presentation/Fixture.swift"
expect_result 0 'Architecture verifier passed'
echo 'Architecture verifier regression tests passed'

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

check_no_imports() {
  local label="$1"
  local path="$2"
  shift 2
  for import_name in "$@"; do
    if rg -n "^import ${import_name}\\b" "$ROOT/$path"; then
      echo "Architecture violation: $label must not import $import_name" >&2
      failures=$((failures + 1))
    fi
  done
}

check_no_imports "Domain" "Sources/NessaFeatures/Domain" SwiftUI UIKit Combine NessaDesignSystem NessaObservability
check_no_imports "Application" "Sources/NessaFeatures/Application" SwiftUI UIKit Combine NessaDesignSystem

if rg -n 'NessaGatewayClient\(|NessaCredentialStore\(|UserDefaultsChatPreferences\(|MockRepository\(' "$ROOT/Sources/NessaFeatures/Presentation"; then
  echo "Architecture violation: presentation must receive adapters through composition" >&2
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

echo "Architecture verifier passed"

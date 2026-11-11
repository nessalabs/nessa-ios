#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

if ! command -v rg >/dev/null 2>&1; then
  echo "Architecture verifier requires ripgrep (rg)." >&2
  exit 1
fi

check_absent() {
  local pattern="$1"
  local path="$2"
  local violation="$3"
  local status
  if rg -n "$pattern" "$ROOT/$path"; then
    echo "Architecture violation: $violation" >&2
    failures=$((failures + 1))
  else
    status=$?
    if [[ "$status" -ne 1 ]]; then
      echo "Architecture verifier could not scan $path (rg exit $status)." >&2
      exit 1
    fi
  fi
}

check_no_imports() {
  local label="$1"
  local path="$2"
  shift 2
  for import_name in "$@"; do
    check_absent "^import ${import_name}\\b" "$path" "$label must not import $import_name"
  done
}

check_no_imports "Domain" "Sources/NessaFeatures/Domain" SwiftUI UIKit Combine NessaDesignSystem NessaObservability
check_no_imports "Application" "Sources/NessaFeatures/Application" SwiftUI UIKit Combine NessaDesignSystem

check_absent 'NessaGatewayClient\(|NessaCredentialStore\(|UserDefaultsChatPreferences\(|MockRepository\(' \
  "Sources/NessaFeatures/Presentation" "presentation must receive adapters through composition"

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

echo "Architecture verifier passed"

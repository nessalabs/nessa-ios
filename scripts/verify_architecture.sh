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

check_no_imports "Domain" "Sources/ClawdiaFeatures/Domain" SwiftUI UIKit Combine ClawdiaDesignSystem ClawdiaObservability
check_no_imports "Application" "Sources/ClawdiaFeatures/Application" SwiftUI UIKit ClawdiaDesignSystem

if rg -n "^import SwiftUI\\b|^import UIKit\\b" "$ROOT/Sources/SharedKernel" "$ROOT/Sources/ClawdiaObservability"; then
  echo "Architecture violation: SharedKernel and Observability must stay UI-free" >&2
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

echo "Architecture verifier passed"

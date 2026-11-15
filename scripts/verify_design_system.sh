#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

if rg -n "Color\\(hex:|\\.font\\(\\.system|cornerRadius: [0-9]" "$ROOT/Sources/NessaFeatures/Presentation"; then
  echo "Design-system violation: feature presentation must use NessaDesignSystem tokens/components for colors, type, and radii" >&2
  failures=$((failures + 1))
fi

# The shipped transcript consumes generated Contract styles. Compare them to the
# canonical Swift tokens instead of requiring a token reference in a SwiftUI view.
"$ROOT/scripts/export-bubble-style.sh" --check

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

echo "Design-system verifier passed"

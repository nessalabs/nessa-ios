#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

if rg -n "Color\\(hex:|\\.font\\(\\.system|cornerRadius: [0-9]" "$ROOT/Sources/NessaFeatures/Presentation"; then
  echo "Design-system violation: feature presentation must use NessaDesignSystem tokens/components for colors, type, and radii" >&2
  failures=$((failures + 1))
fi

if ! rg -q "NessaColor|NessaType|NessaSpacing|NessaRadius|NessaCard|NessaPrimaryButton|NessaPillButton" "$ROOT/Sources/NessaFeatures/Presentation"; then
  echo "Design-system violation: presentation layer is not using the shared design system" >&2
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

echo "Design-system verifier passed"

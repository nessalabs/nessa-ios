#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:---check}" in --check|--write) ;; *) echo "Use --check or --write" >&2; exit 2 ;; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
xcrun swiftc -parse-as-library \
  Sources/NessaDesignSystem/DesignTokens.swift Sources/NessaDesignSystem/MessageBubbleTokens.swift \
  nessa/tools/export-bubble-style.swift -o "$tmp/export"
"$tmp/export" > "$tmp/bubble-style.contract"
if [[ "${1:---check}" == --write ]]; then
  cp "$tmp/bubble-style.contract" nessa/bubble-style.contract
elif ! diff -u nessa/bubble-style.contract "$tmp/bubble-style.contract"; then
  echo "Update Exact's bubble styles with scripts/export-bubble-style.sh --write" >&2
  exit 1
fi

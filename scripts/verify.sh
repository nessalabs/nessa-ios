#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/verify_architecture.sh"
"$ROOT/scripts/verify_design_system.sh"
swift build --package-path "$ROOT"
swift test --package-path "$ROOT"

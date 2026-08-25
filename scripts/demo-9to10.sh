#!/usr/bin/env bash
# Compatibility wrapper — prefer ./scripts/demo.sh rhel9 (or demo.sh for both).
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/demo.sh" rhel9 "$@"

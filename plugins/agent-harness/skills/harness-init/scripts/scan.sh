#!/usr/bin/env bash
# Thin wrapper: the scan lives in the plugin's scripts/scan.py.
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/scan.py" "$@"

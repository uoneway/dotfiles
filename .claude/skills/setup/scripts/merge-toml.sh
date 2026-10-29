#!/bin/bash
# Usage: merge-toml.sh BASE TARGET [--check] [--migrations FILE]
set -e
exec python3 "$(dirname "$0")/merge-settings.py" "$@"

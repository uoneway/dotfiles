#!/usr/bin/env bash
# Copy to config/installers/my-tool.sh and implement the marked steps.
set -euo pipefail

requested_version="${1:?pass latest or an exact x.y.z version}"
: "${DOTFILES_APP_NAME:?run through dotfiles install}"

# 1. Resolve latest when requested_version is latest.
# 2. Check the installed version; skip if it already matches.
# 3. Download and install the requested version under the user's home.
# 4. Verify the installed version. Exit nonzero on failure.
# Keep machine state and credentials outside config. Do not append to shell rc.

printf 'Implement installation of %s (%s) in this script first.\n' "$DOTFILES_APP_NAME" "$requested_version" >&2
exit 64

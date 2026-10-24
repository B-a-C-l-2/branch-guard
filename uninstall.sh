#!/bin/sh
# Remove branch-guard. Only unsets the global hooksPath if it points at
# the directory we installed into.
set -e
dest="$HOME/.git-hooks"
rm -f "$dest/pre-commit"
current=$(git config --global --get core.hooksPath 2>/dev/null || true)
if [ "$current" = "$dest" ]; then
    git config --global --unset core.hooksPath
    echo "branch-guard: global core.hooksPath unset"
fi
echo "branch-guard: uninstalled"

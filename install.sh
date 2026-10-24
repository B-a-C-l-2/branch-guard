#!/bin/sh
# Install branch-guard's pre-commit hook.
#
#   ./install.sh           global: every repo on this machine (recommended —
#                          agents clone repos of their own while they work,
#                          and a hook inside one repo is not in a clone made
#                          five minutes later)
#   ./install.sh --local   this repo only
set -e
src_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "$1" = "--local" ]; then
    dest=$(git rev-parse --git-dir)/hooks
else
    dest="$HOME/.git-hooks"
    git config --global core.hooksPath "$dest"
fi

mkdir -p "$dest"
cp "$src_dir/hooks/pre-commit" "$dest/pre-commit"
chmod +x "$dest/pre-commit"
echo "branch-guard: installed pre-commit hook into $dest"
if [ "$1" != "--local" ]; then
    echo "branch-guard: core.hooksPath set globally -> $dest"
    echo "branch-guard: note - repos using husky override this; see README."
fi

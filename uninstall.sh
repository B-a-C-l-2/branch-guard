#!/bin/sh
# Remove branch-guard. Only unsets the global hooksPath if it points at
# the directory we installed into.
set -e
dest="$HOME/.git-hooks"
rm -f "$dest/pre-commit"
current=$(git config --global --get core.hooksPath 2>/dev/null || true)

# install and uninstall may run under different shells on Windows, so the
# stored value can be C:/... (or C:\...) while $HOME expands to /c/...
# (MSYS form). `[ = ]` is a pure string comparison with no filesystem
# awareness, so both sides are normalized first or the unset is silently
# skipped. cygpath -m emits the Windows form with forward slashes, which
# collapses all three spellings without any backslash handling. On plain
# Unix there is nothing to normalize and this is a pass-through.
normalize() {
    p=$1
    if command -v cygpath >/dev/null 2>&1; then
        p=$(cygpath -m -- "$p" 2>/dev/null || printf '%s' "$p")
    fi
    printf '%s' "$p" | sed 's:/*$::' | tr 'A-Z' 'a-z'
}

if [ -n "$current" ] && [ "$(normalize "$current")" = "$(normalize "$dest")" ]; then
    git config --global --unset core.hooksPath
    echo "branch-guard: global core.hooksPath unset"
fi
echo "branch-guard: uninstalled"

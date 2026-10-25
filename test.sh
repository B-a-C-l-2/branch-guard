#!/bin/sh
# branch-guard acceptance tests. Scenarios 1-8 map to the acceptance list in
# docs/DESIGN.md; scenario 9 is a regression test for uninstall. Run: ./test.sh
set -e
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
pass=0; fail=0

# Run a command with a clean, controlled marker environment.
as_human() { (unset CLAUDECODE CODEX_THREAD_ID CODEX_SESSION_ID AGENT_GUARD AGENT_GUARD_APPROVE; "$@"); }
as_agent() { (unset CLAUDECODE CODEX_SESSION_ID AGENT_GUARD AGENT_GUARD_APPROVE; CODEX_THREAD_ID=test "$@"); }
# like as_agent, but HOME points at $h so global config is sandboxed
as_agent_h() { (unset CLAUDECODE CODEX_SESSION_ID AGENT_GUARD AGENT_GUARD_APPROVE; HOME="$h" CODEX_THREAD_ID=test "$@"); }

# fresh playground repo with one commit on main; prints its path
setup_repo() {
    dir=$(mktemp -d)
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name Test
    git -C "$dir" config core.hooksPath "$dir/.git/hooks"   # hermetic: repo-level beats any machine-global hooksPath
    cp "$here/hooks/pre-commit" "$dir/.git/hooks/pre-commit"
    chmod +x "$dir/.git/hooks/pre-commit"
    echo x > "$dir/file.txt"
    git -C "$dir" add file.txt 2>/dev/null
    as_human git -C "$dir" commit -qm init
    printf "%s" "$dir"
}

check() { # name actual expected
    if [ "$2" = "$3" ]; then
        pass=$((pass+1)); echo "ok   - $1"
    else
        fail=$((fail+1)); echo "FAIL - $1 (expected [$3], got [$2])"
    fi
}

echo "== scenario 1: agent commits on main -> work moved to a new branch"
r=$(setup_repo)
echo change >> "$r/file.txt"
as_agent git -C "$r" add file.txt 2>/dev/null
out=$(as_agent git -C "$r" commit -m work 2>&1)
check "agent got moved off main" "$(git -C "$r" symbolic-ref --short HEAD | cut -d/ -f1)" "agent"
check "main has no new commit" "$(git -C "$r" log main --oneline | wc -l | tr -d ' ')" "1"
check "work landed on the new branch" "$(git -C "$r" log HEAD --oneline | wc -l | tr -d ' ')" "2"

echo "== scenario 2: human commits on main -> untouched"
r=$(setup_repo)
echo change >> "$r/file.txt"
as_human git -C "$r" add file.txt 2>/dev/null
as_human git -C "$r" commit -qm work
check "human stays on main" "$(git -C "$r" symbolic-ref --short HEAD)" "main"
check "human commit on main" "$(git -C "$r" log main --oneline | wc -l | tr -d ' ')" "2"

echo "== scenario 3: agent on a feature branch -> untouched"
r=$(setup_repo)
git -C "$r" switch -qc feature
echo change >> "$r/file.txt"
as_agent git -C "$r" add file.txt 2>/dev/null
as_agent git -C "$r" commit -qm work
check "agent stays on feature" "$(git -C "$r" symbolic-ref --short HEAD)" "feature"

echo "== scenario 4: agent with AGENT_GUARD_APPROVE=1 on main -> allowed"
r=$(setup_repo)
echo change >> "$r/file.txt"
(unset CLAUDECODE CODEX_SESSION_ID AGENT_GUARD; CODEX_THREAD_ID=test AGENT_GUARD_APPROVE=1 git -C "$r" add file.txt 2>/dev/null)
(unset CLAUDECODE CODEX_SESSION_ID AGENT_GUARD; CODEX_THREAD_ID=test AGENT_GUARD_APPROVE=1 git -C "$r" commit -qm work)
check "approved agent stays on main" "$(git -C "$r" symbolic-ref --short HEAD)" "main"

echo "== scenario 5: configurable list moves work off the configured branch"
r=$(setup_repo)
git -C "$r" config branch-guard.protected develop
git -C "$r" switch -qc develop
echo change >> "$r/file.txt"
as_agent git -C "$r" add file.txt 2>/dev/null
as_agent git -C "$r" commit -qm work
check "agent moved off configured develop" "$(git -C "$r" symbolic-ref --short HEAD | cut -d/ -f1)" "agent"
check "develop has no new commit" "$(git -C "$r" log develop --oneline | wc -l | tr -d ' ')" "1"

echo "== scenario 6: configured list replaces the default (main is no longer protected)"
r=$(setup_repo)
git -C "$r" config branch-guard.protected develop
echo change >> "$r/file.txt"
as_agent git -C "$r" add file.txt 2>/dev/null
as_agent git -C "$r" commit -qm work
check "agent stays on unlisted main" "$(git -C "$r" symbolic-ref --short HEAD)" "main"
check "main got the commit" "$(git -C "$r" log main --oneline | wc -l | tr -d ' ')" "2"

echo "== scenario 7: repo-level config overrides the global one"
r=$(setup_repo)
h=$(mktemp -d)
HOME="$h" git config --global branch-guard.protected develop
git -C "$r" config branch-guard.protected main
echo change >> "$r/file.txt"
as_agent_h git -C "$r" add file.txt 2>/dev/null
as_agent_h git -C "$r" commit -qm work
check "repo-level main is protected" "$(git -C "$r" symbolic-ref --short HEAD | cut -d/ -f1)" "agent"
git -C "$r" switch -qc develop main
echo more >> "$r/file.txt"
as_agent_h git -C "$r" add file.txt 2>/dev/null
as_agent_h git -C "$r" commit -qm more
check "global develop is overridden away" "$(git -C "$r" symbolic-ref --short HEAD)" "develop"

echo "== scenario 8: an empty list protects nothing"
r=$(setup_repo)
git -C "$r" config branch-guard.protected ""
echo change >> "$r/file.txt"
as_agent git -C "$r" add file.txt 2>/dev/null
as_agent git -C "$r" commit -qm work
check "empty list leaves main unprotected" "$(git -C "$r" symbolic-ref --short HEAD)" "main"

echo "== scenario 9 (regression): uninstall when the stored config uses Windows path form"
# install and uninstall can run under different shells on Windows, leaving a
# C:/... value in the config while $HOME expands to /c/... (MSYS form).
# HOME is sandboxed to a temp dir, so the real machine config is untouched.
d=$(mktemp -d)
mkdir -p "$d/.git-hooks"
cp "$here/hooks/pre-commit" "$d/.git-hooks/pre-commit"
winform=$(cd "$d" && pwd -W 2>/dev/null || pwd)   # C:/... on MSYS, plain path elsewhere
HOME="$d" git config --global core.hooksPath "$winform/.git-hooks"
HOME="$d" sh "$here/uninstall.sh" >/dev/null
check "config unset despite path form mismatch" "$(HOME="$d" git config --global --get core.hooksPath 2>/dev/null || echo unset)" "unset"
check "hook file removed" "$([ -f "$d/.git-hooks/pre-commit" ] && echo present || echo gone)" "gone"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

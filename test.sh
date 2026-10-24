#!/bin/sh
# branch-guard acceptance tests. Each scenario maps to one line in the
# acceptance list (docs/DESIGN.md). Run: ./test.sh
set -e
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
pass=0; fail=0

# Run a command with a clean, controlled marker environment.
as_human() { (unset CLAUDECODE CODEX_THREAD_ID CODEX_SESSION_ID AGENT_GUARD AGENT_GUARD_APPROVE; "$@"); }
as_agent() { (unset CLAUDECODE CODEX_SESSION_ID AGENT_GUARD AGENT_GUARD_APPROVE; CODEX_THREAD_ID=test "$@"); }

# fresh playground repo with one commit on main; prints its path
setup_repo() {
    dir=$(mktemp -d)
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name Test
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

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

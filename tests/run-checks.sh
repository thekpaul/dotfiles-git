#!/usr/bin/env bash
# Parse and behaviour checks for the Git configuration files.
#
# Pure Bash driving the `git` binary named by $GIT_BIN (default: `git`), so
# CI can point this at any leg of a version matrix.
#
# Usage:
#     bash tests/run-checks.sh
#     GIT_BIN=git2.28 bash tests/run-checks.sh
#
# Exits non-zero if any check fails; prints a per-check PASS/FAIL summary.

set -uo pipefail

# Resolve the repo root from this script's location, independent of CWD.
_self="${BASH_SOURCE[0]}"
REPO_ROOT="$(cd "${_self%/*}/.." && pwd)"
cd "$REPO_ROOT" || exit 1

GIT_BIN="${GIT_BIN:-git}"
command -v "$GIT_BIN" >/dev/null 2>&1 || {
    printf 'FATAL: git binary "%s" not found on PATH\n' "$GIT_BIN" >&2
    exit 1
}

_failures=0

# check NAME COMMAND...
# Runs COMMAND in a subshell; reports PASS on exit 0, FAIL otherwise.
check() {
    local name="$1"; shift
    if ( "$@" ); then
        printf 'PASS  %s\n' "$name"
    else
        printf 'FAIL  %s\n' "$name"
        _failures=$(( _failures + 1 ))
    fi
}

# Creates a throwaway HOME + XDG_CONFIG_HOME tree with this repo symlinked in
# as the Git config directory, so `$XDG_CONFIG_HOME/git/config` —
# and therefore the module's own `config` — IS the isolated global Git config.
# Echoes the tree's root path; caller is responsible for `rm -rf` on it.
setup_home() {
    local tmp
    tmp="$(mktemp -d)" || return 1
    mkdir -p "$tmp/home" "$tmp/config" || return 1
    ln -s "$REPO_ROOT" "$tmp/config/git" || return 1
    printf '%s' "$tmp"
}

# Runs `$GIT_BIN` with HOME/XDG_CONFIG_HOME pointed at an isolated tree
# (built by setup_home), so the real user's Git config cannot leak in and
# this repo's `config` is the only global config in effect.
# `commit.gpgsign` is forced off: the module config signs by default, and
# no signing key is available in this isolated/CI environment —
# every check below exercises alias/format behaviour, never the signing path.
isolated_git() {
    local tree="$1"; shift
    HOME="$tree/home" \
    XDG_CONFIG_HOME="$tree/config" \
    GIT_CONFIG_NOSYSTEM=1 \
        "$GIT_BIN" -c commit.gpgsign=false "$@"
}

# ── 1. Parse: `config` loads as valid Git config ─────────────────────────────
config_parse_check() {
    "$GIT_BIN" config --file config --list >/dev/null
}
check "parse (config --list)" config_parse_check

# ── 2. Parse: `windows.config` loads as valid Git config ─────────────────────
windows_config_parse_check() {
    "$GIT_BIN" config --file windows.config --list >/dev/null
}
check "parse (windows.config --list)" windows_config_parse_check

# ── 3. Pretty formats: `simple`/`expand` are registered as expected ──────────
pretty_regexp_check() {
    local out
    out="$("$GIT_BIN" config --file config --get-regexp '^pretty\.')" || return 1
    [[ "$out" == *"pretty.simple "* ]] || return 1
    [[ "$out" == *"pretty.expand "* ]] || return 1
}
check "pretty formats registered (simple, expand)" pretty_regexp_check

# ── 4. Pretty formats: render in a scratch repo ──────────────────────────────
# Asserts the hash/title line, the date line, and — for `expand` only —
# both the committer and author identity lines.
pretty_render_check() {
    local tree repo out
    tree="$(setup_home)" || return 1
    trap 'rm -rf "$tree"; trap - RETURN' RETURN
    repo="$tree/repo"
    mkdir -p "$repo" || return 1
    cd "$repo" || return 1
    isolated_git "$tree" init -q -b main || return 1
    printf 'hello\n' > file.txt || return 1
    isolated_git "$tree" add file.txt || return 1
    GIT_AUTHOR_NAME="Test User" GIT_AUTHOR_EMAIL="test@example.com" \
    GIT_COMMITTER_NAME="Test User" GIT_COMMITTER_EMAIL="test@example.com" \
        isolated_git "$tree" commit -q -m "Test Commit" || return 1

    out="$(isolated_git "$tree" log --pretty=simple -1)" || return 1
    [[ "$(head -n1 <<<"$out")" =~ ^[0-9a-f]{4,}\  ]] || return 1
    [[ "$out" == *"Test Commit"* ]] || return 1
    [[ "$out" == *"Committed on"* ]] || return 1

    out="$(isolated_git "$tree" log --pretty=expand -1)" || return 1
    [[ "$(head -n1 <<<"$out")" =~ ^[0-9a-f]{4,}\  ]] || return 1
    [[ "$out" == *"Test Commit"* ]] || return 1
    [[ "$out" == *"Committed on"*"by Test User <test@example.com>"* ]] || return 1
    [[ "$out" == *"Authored"*"on"*"by Test User <test@example.com>"* ]] || return 1
}
check "pretty render (simple, expand identities)" pretty_render_check

# ── 5. rst-commit: resets the author and reuses HEAD's message ───────────────
# GIT_EDITOR=true stands in for an editor that accepts the pre-filled message
# unmodified, so --reedit-message needs no human interaction here.
rst_commit_check() {
    local tree repo out
    tree="$(setup_home)" || return 1
    trap 'rm -rf "$tree"; trap - RETURN' RETURN
    repo="$tree/repo"
    mkdir -p "$repo" || return 1
    cd "$repo" || return 1
    isolated_git "$tree" init -q -b main || return 1
    printf 'a\n' > file.txt || return 1
    isolated_git "$tree" add file.txt || return 1
    GIT_AUTHOR_NAME="Someone Else" GIT_AUTHOR_EMAIL="else@example.com" \
    GIT_COMMITTER_NAME="Someone Else" GIT_COMMITTER_EMAIL="else@example.com" \
        isolated_git "$tree" commit -q -m "Reusable Message" || return 1

    printf 'b\n' > file2.txt || return 1
    isolated_git "$tree" add file2.txt || return 1
    GIT_EDITOR=true isolated_git "$tree" rst-commit >/dev/null 2>&1 || return 1

    out="$(isolated_git "$tree" log -1 --format='%s|%an|%ae')" || return 1
    [[ "$out" == "Reusable Message|Paul Kim|44695374+thekpaul@users.noreply.github.com" ]]
}
check "rst-commit (reset author, reuse message)" rst_commit_check

# ── 6. fix-commit: recovers a failed commit's message (normal repo) ──────────
# A failing commit-msg hook leaves .git/COMMIT_EDITMSG populated
# (that hook only runs after the message file is written) but aborts the commit;
# fix-commit re-invokes commit against that leftover file.
# A pre-commit hook would abort too early — before COMMIT_EDITMSG is written.
fix_commit_check() {
    local tree repo out
    tree="$(setup_home)" || return 1
    trap 'rm -rf "$tree"; trap - RETURN' RETURN
    repo="$tree/repo"
    mkdir -p "$repo" || return 1
    cd "$repo" || return 1
    isolated_git "$tree" init -q -b main || return 1
    printf 'a\n' > file.txt || return 1
    isolated_git "$tree" add file.txt || return 1
    mkdir -p .git/hooks || return 1
    printf '#!/bin/sh\nexit 1\n' > .git/hooks/commit-msg || return 1
    chmod +x .git/hooks/commit-msg || return 1

    isolated_git "$tree" commit -m "Recovered Message" >/dev/null 2>&1 && return 1
    [[ -f .git/COMMIT_EDITMSG ]] || return 1
    rm -f .git/hooks/commit-msg

    GIT_EDITOR=true isolated_git "$tree" fix-commit >/dev/null 2>&1 || return 1
    out="$(isolated_git "$tree" log -1 --format='%s')" || return 1
    [[ "$out" == "Recovered Message" ]]
}
check "fix-commit (normal repo)" fix_commit_check

# ── 7. fix-commit: recovers a failed commit's message (linked worktree) ──────
# The historical bug this alias fixed: a worktree's top-level `.git` is
# a file, not a directory, and COMMIT_EDITMSG for a worktree lives under
# the main repo's `.git/worktrees/<name>/`, not `.git/` itself —
# only `git rev-parse --git-path COMMIT_EDITMSG` resolves the right file.
fix_commit_worktree_check() {
    local tree repo wt out
    tree="$(setup_home)" || return 1
    trap 'rm -rf "$tree"; trap - RETURN' RETURN
    repo="$tree/repo"
    wt="$tree/wt"
    mkdir -p "$repo" || return 1
    cd "$repo" || return 1
    isolated_git "$tree" init -q -b main || return 1
    printf 'a\n' > file.txt || return 1
    isolated_git "$tree" add file.txt || return 1
    isolated_git "$tree" commit -q -m "Initial" || return 1
    isolated_git "$tree" branch feature || return 1
    isolated_git "$tree" worktree add -q "$wt" feature || return 1

    cd "$wt" || return 1
    [[ -f .git ]] || return 1   # confirms the worktree's `.git` is a file
    printf 'b\n' > file2.txt || return 1
    isolated_git "$tree" add file2.txt || return 1
    mkdir -p "$repo/.git/hooks" || return 1   # hooks are shared from the main repo
    printf '#!/bin/sh\nexit 1\n' > "$repo/.git/hooks/commit-msg" || return 1
    chmod +x "$repo/.git/hooks/commit-msg" || return 1

    isolated_git "$tree" commit -m "Worktree Recovered" >/dev/null 2>&1 && return 1
    [[ -f "$(isolated_git "$tree" rev-parse --git-path COMMIT_EDITMSG)" ]] || return 1
    rm -f "$repo/.git/hooks/commit-msg"

    GIT_EDITOR=true isolated_git "$tree" fix-commit >/dev/null 2>&1 || return 1
    out="$(isolated_git "$tree" log -1 --format='%s')" || return 1
    [[ "$out" == "Worktree Recovered" ]]
}
check "fix-commit (linked worktree)" fix_commit_worktree_check

# ── 8. windows.config: option names and values are as expected ───────────────
windows_config_options_check() {
    local out
    out="$("$GIT_BIN" config --file windows.config --get gpg.program)" || return 1
    [[ "$out" == '~/.config/git/bin/gpg.cmd' ]] || return 1
    out="$("$GIT_BIN" config --file windows.config --get core.longpaths)" || return 1
    [[ "$out" == "true" ]]
}
check "windows.config sanity (gpg.program, core.longpaths)" windows_config_options_check

# ── Summary ──────────────────────────────────────────────────────────────────
echo "─────────────────────────────────────────"
if (( _failures == 0 )); then
    echo "All checks passed."
    exit 0
fi
printf '%d check(s) failed.\n' "$_failures"
exit 1

#!/usr/bin/env bash
# Tests for the Makefile. Runs in a throwaway HOME and tmux socket directory,
# so it never touches the real sessions or dotfiles.
# Network tests (plugin install + pinned commits): RUN_NETWORK=1 tests/test.sh
# `cond && ok ... || fail ...` is safe here: ok only echoes, so it never fails and trips the `||`.
# shellcheck disable=SC2015
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# No dots in the path: tmux rewrites "." and ":" inside session names.
WORK=$(mktemp -d /tmp/tmguiaXXXXXX)
export HOME="$WORK/home" TMUX_TMPDIR="$WORK/tmux"
mkdir -p "$HOME" "$TMUX_TMPDIR"
unset TMUX
trap 'tmux kill-server 2>/dev/null; rm -rf "$WORK"' EXIT

fails=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
check() { # check "description" command...
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$d"; else fail "$d"; fi
}
tm() { make --no-print-directory -C "$REPO" "$@"; }

# --- help and dry runs -------------------------------------------------------
check "help runs" tm help
for t in ls attach create detach rename kill clean kill-all install conf alias plugins boot setup; do
  check "dry run: $t" tm -n "$t" S=x N=y
done

# TPM must be pinned before anything executes it (source-file loads it).
pin_line=$(tm -n plugins | grep -n 'tpm checkout' | head -1 | cut -d: -f1)
run_line=$(tm -n plugins | grep -n 'source-file' | head -1 | cut -d: -f1)
[ -n "$pin_line" ] && [ -n "$run_line" ] && [ "$pin_line" -lt "$run_line" ] \
  && ok "plugins: TPM is pinned before it runs" || fail "plugins: TPM runs before being pinned"

# --- session names are data, never commands ---------------------------------
tm create S="a b;touch $WORK/pwned" >/dev/null 2>&1
[ ! -e "$WORK/pwned" ] && ok "create: ; in name is not executed" || fail "create: ; in name was executed"
tmux has-session -t "a b;touch $WORK/pwned" 2>/dev/null && ok "create: odd name kept as is" || fail "create: odd name not kept"

# shellcheck disable=SC2016 # the literal $() is the point of the test
tm rename S="a b;touch $WORK/pwned" N='$(touch '"$WORK"'/pwned2) x' >/dev/null 2>&1
[ ! -e "$WORK/pwned2" ] && ok "rename: \$() in new name is not executed" || fail "rename: \$() in new name was executed"

tm detach S="x; touch $WORK/pwned3" >/dev/null 2>&1
[ ! -e "$WORK/pwned3" ] && ok "detach: ; in name is not executed" || fail "detach: ; in name was executed"

tm create S=work >/dev/null 2>&1
tm kill S=work >/dev/null 2>&1
tmux has-session -t work 2>/dev/null && fail "kill: session still alive" || ok "kill removes the session"
check "need: missing name fails" bash -c "! make --no-print-directory -C '$REPO' kill"

# --- conf and alias are idempotent, alias path is quoted --------------------
tm conf >/dev/null 2>&1
[ "$(readlink -f "$HOME/.tmux.conf")" = "$REPO/tmux.conf" ] && ok "conf links tmux.conf" || fail "conf link wrong"
tm conf >/dev/null 2>&1
[ ! -e "$HOME/.tmux.conf.bak" ] && ok "conf is idempotent (no .bak)" || fail "conf made a .bak on 2nd run"

tm alias >/dev/null 2>&1; tm alias >/dev/null 2>&1
[ "$(grep -c '^alias tm=' "$HOME/.bashrc")" = 1 ] && ok "alias added once" || fail "alias duplicated or missing"
grep -qF -- "-C \"$REPO\"" "$HOME/.bashrc" && ok "alias quotes the repo path" || fail "alias path not quoted"

# --- tmux.conf keeps the setting that prevents the boot hang ----------------
grep -q "^set -g @continuum-boot 'on'" "$REPO/tmux.conf" \
  && ok "tmux.conf sets @continuum-boot on" || fail "tmux.conf lost @continuum-boot on"

# --- network: plugins install and stay on the pinned commits ---------------
if [ "${RUN_NETWORK:-0}" = 1 ]; then
  tm plugins >/dev/null 2>&1 && ok "plugins install" || fail "plugins install"
  for p in "tpm TPM" "tmux-resurrect RESURRECT" "tmux-continuum CONTINUUM"; do
    read -r dir var <<<"$p"
    want=$(sed -n "s/^${var}_SHA := //p" "$REPO/Makefile")
    got=$(git -C "$HOME/.tmux/plugins/$dir" rev-parse HEAD 2>/dev/null)
    [ -n "$want" ] && [ "$want" = "$got" ] && ok "$dir pinned to $want" || fail "$dir not on pinned commit"
  done
  [ "$(stat -c %a "$HOME/.local/share/tmux/resurrect")" = 700 ] && ok "resurrect dir is 700" || fail "resurrect dir not 700"
fi

echo
[ "$fails" = 0 ] && echo "all passed" || echo "$fails failed"
exit "$fails"

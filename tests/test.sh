#!/usr/bin/env bash
# Tests for bin/tm. Runs in a throwaway HOME and tmux socket directory,
# so it never touches the real sessions or dotfiles. Every fixed bug keeps a test here.
# Network tests (plugin install, pinned commits, save/restore): RUN_NETWORK=1 tests/test.sh
# `cond && ok ... || fail ...` is safe here: ok only echoes, so it never fails and trips the `||`.
# shellcheck disable=SC2015,SC2016,SC2088,SC2329 # &&/|| as above; literal $ in patterns; helpers run via eval/q
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# No dots in the path: tmux rewrites "." and ":" inside session names.
WORK=$(mktemp -d /tmp/tmguiaXXXXXX)
export HOME="$WORK/home" TMUX_TMPDIR="$WORK/tmux" XDG_DATA_HOME="$WORK/home/.local/share" XDG_CONFIG_HOME="$WORK/home/.config"
mkdir -p "$HOME" "$TMUX_TMPDIR" "$WORK/bin"
# Nothing from the real terminal may leak in: tm open would pick it and open real windows.
unset TMUX TMUX_PANE TM_TERMINAL KITTY_WINDOW_ID KITTY_LISTEN_ON WEZTERM_PANE KONSOLE_VERSION GNOME_TERMINAL_SCREEN
trap 'tmux kill-server 2>/dev/null; rm -rf "$WORK"' EXIT

fails=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
check() { # check "description" command...
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$d"; else fail "$d"; fi
}
tm() { "$REPO/bin/tm" "$@"; }
q() { "$@" >/dev/null 2>&1; }  # quiet
wait_for() { # wait_for "shell condition" (up to 10 s)
  local _
  for _ in $(seq 100); do eval "$1" && return 0; sleep 0.1; done
  return 1
}
# A stub program that logs its arguments, one call per line, to $WORK/NAME.log.
stub() { printf '#!/bin/sh\necho "$*" >> "%s/%s.log"\n' "$WORK" "$1" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
# A real client on a session, so it counts as "in use". script gives it a terminal;
# the sleep keeps its stdin open (EOF would end it).
attach_client() { sleep 60 | script -qfc "tmux attach -t '=$1'" /dev/null >/dev/null 2>&1 & }
attached() { [ "$(tmux display -p -t "=$1:" '#{session_attached}' 2>/dev/null)" -gt 0 ] 2>/dev/null; }
# Runs tm as if typed inside a pane of SESSION (TMUX/TMUX_PANE set like tmux does).
tm_inside() { local s=$1; shift
  TMUX="$(tmux display -p -t "=$s:" '#{socket_path},0,#{session_id}')" TMUX_PANE="$(tmux display -p -t "=$s:" '#{pane_id}')" tm "$@"; }

# --- help and the command list ---------------------------------------------
check "help runs" tm help
check "version runs" tm version
commands=$(tm _commands)
[ -n "$commands" ] && ok "commands: $(echo "$commands" | tr '\n' ' ')" || fail "no commands listed"
# Every listed command is in the help and handled by the dispatcher (and the other way round).
for c in $commands; do
  tm help | grep -q "^  $c " || fail "help misses $c"
  grep -qE "^  ($c|$c\|[^)]*)\) " "$REPO/bin/tm" || fail "dispatcher misses $c"
done
handled=$(sed -n 's/^  \([a-z-]*\)[|)].*/\1/p' "$REPO/bin/tm" | grep -v '^_' | sort -u)
[ "$handled" = "$(echo "$commands" | sort -u)" ] && ok "help, completion and dispatcher list the same commands" \
  || fail "command lists differ: $(diff <(echo "$handled") <(echo "$commands" | sort -u) | tr '\n' ' ')"
q tm nope && fail "unknown command should fail" || ok "unknown command fails"
[ "$(tm </dev/null)" = "$(tm help)" ] && ok "tm with no arguments and no terminal shows the help" || fail "tm alone did not show the help"

# TPM must be pinned before anything executes it (source-file loads it).
body=$(sed -n '/^cmd_plugins()/,/^}/p' "$REPO/bin/tm")
pin_line=$(echo "$body" | grep -n 'pin "$PLUGINS/tpm"' | head -1 | cut -d: -f1)
run_line=$(echo "$body" | grep -n 'source-file' | head -1 | cut -d: -f1)
[ -n "$pin_line" ] && [ -n "$run_line" ] && [ "$pin_line" -lt "$run_line" ] \
  && ok "plugins: TPM is pinned before it runs" || fail "plugins: TPM runs before being pinned"

# --- the old make alias is pointed to the new tm ----------------------------
out=$(make --no-print-directory -C "$REPO" attach work 2>&1)
echo "$out" | grep -q 'now a command of bin/tm' && ok "make attach (old alias): explains the move" || fail "make attach: no hint"

# --- names are data: commands, spaces, ; and $() ------------------------------
q tm create clean; q tm create other
q tm kill clean
{ ! tmux has-session -t =clean 2>/dev/null && tmux has-session -t =other 2>/dev/null; } \
  && ok "kill clean: a session named like a command is just a name" || fail "kill clean: wrong result"
q tm kill other

q tm create "a b;touch $WORK/pwned"
[ ! -e "$WORK/pwned" ] && ok "create: ; in name is not executed" || fail "create: ; in name was executed"
tmux has-session -t "=a b;touch $WORK/pwned" 2>/dev/null && ok "create: odd name kept as is" || fail "create: odd name not kept"
# shellcheck disable=SC2016 # the literal $() is the point of the test
q tm rename "a b;touch $WORK/pwned" '$(touch '"$WORK"'/pwned2) x'
[ ! -e "$WORK/pwned2" ] && ok "rename: \$() in new name is not executed" || fail "rename: \$() in new name was executed"
q tm detach "x; touch $WORK/pwned3"
[ ! -e "$WORK/pwned3" ] && ok "detach: ; in name is not executed" || fail "detach: ; in name was executed"
q tm create -x
tmux has-session -t =-x 2>/dev/null && ok "create: a name starting with - is a name, not an option" || fail "create: -x not created"
tmux kill-server 2>/dev/null

q tm create work
q tm create work && fail "create: a second create should fail" || ok "create: refuses an existing name"
q tm kill work
tmux has-session -t =work 2>/dev/null && fail "kill: session still alive" || ok "kill removes the session"
q tm kill && fail "kill without a name should fail" || ok "kill: missing name fails"

# tmux turns "." into "_": create reports the real name, and attach finds it.
out=$(tm create a.b 2>&1)
echo "$out" | grep -q "'a_b' created" && tmux has-session -t =a_b 2>/dev/null \
  && ok "create a.b: reports the name tmux used (a_b)" || fail "create a.b: $out"

# create/attach NAME DIR: the session starts in DIR.
mkdir -p "$WORK/proj dir"
q tm create proj "$WORK/proj dir"
[ "$(tmux display -p -t =proj: '#{pane_current_path}')" = "$WORK/proj dir" ] && ok "create NAME DIR: starts in DIR" || fail "create NAME DIR: wrong folder"
q tm create nodir "$WORK/missing" && fail "create with a missing DIR should fail" || ok "create: missing DIR fails"
tmux kill-server 2>/dev/null

# --- exact targets: "pro" must never pick "projeto" by prefix ---------------
q tm create projeto
q tm kill pro; q tm rename pro x; q tm detach pro
tmux has-session -t =projeto 2>/dev/null && ok "kill/rename/detach: no prefix match" || fail "hit 'projeto' via prefix 'pro'"
tmux kill-server 2>/dev/null

# --- clean, attach inside tmux (needs a real client) ------------------------
q tm create "a b"; q tm create busy
attach_client busy
if wait_for "attached busy"; then
  q tm clean
  ! tmux has-session -t "=a b" 2>/dev/null && ok "clean: kills a free session with a space in its name" || fail "clean: skipped 'a b'"
  tmux has-session -t =busy 2>/dev/null && ok "clean: keeps sessions in use" || fail "clean: killed a session in use"

  # Inside tmux, attach switches the current client instead of nesting one.
  q tm create other
  q tm_inside busy attach other
  attached other && ok "attach inside tmux: switches the client" || fail "attach inside tmux: did not switch"
  q tm_inside other attach brand-new "$WORK/proj dir"
  { attached brand-new && [ "$(tmux display -p -t =brand-new: '#{pane_current_path}')" = "$WORK/proj dir" ]; } \
    && ok "attach inside tmux: creates a missing session in DIR and switches" || fail "attach inside tmux: missing session not created"
else
  fail "could not attach a test client (is 'script' installed?)"
fi
tmux kill-server 2>/dev/null

# --- open: terminals are stubbed and log their arguments --------------------
stub gnome-terminal; stub xfce4-terminal; stub xterm
q tm create oa; q tm create "o b"; q tm create busy
attach_client busy
wait_for "attached busy" || fail "open: test client did not attach"
TM_TERMINAL="$WORK/bin/gnome-terminal" q tm open
log=$WORK/gnome-terminal.log
# Order follows "tmux ls" (alphabetical): only the first call opens a window.
{ [ "$(wc -l < "$log")" = 2 ] && head -1 "$log" | grep -q -- '^--window ' && [ "$(grep -c -- '^--tab ' "$log")" = 1 ] \
  && grep -qx -- '--[a-z]* -- env -u TMUX -u TMUX_PANE tmux attach-session -t =oa' "$log" \
  && grep -qx -- '--[a-z]* -- env -u TMUX -u TMUX_PANE tmux attach-session -t =o b' "$log"; } \
  && ok "open: free sessions only, first in a window, the rest in tabs, TMUX unset" || fail "open: wrong calls: $(tr '\n' '|' < "$log")"
: > "$log"; TM_TERMINAL="$WORK/bin/gnome-terminal" q tm open --all
[ "$(wc -l < "$log")" = 3 ] && grep -q '=busy$' "$log" && ok "open --all: includes sessions in use" || fail "open --all: $(tr '\n' '|' < "$log")"
: > "$log"; TM_TERMINAL="$WORK/bin/gnome-terminal" q tm open "o b"
[ "$(cat "$log")" = "--window -- env -u TMUX -u TMUX_PANE tmux attach-session -t =o b" ] && ok "open NAME: only that session" || fail "open NAME: $(cat "$log")"
TM_TERMINAL="$WORK/bin/gnome-terminal" q tm open nope && fail "open: a missing session should fail" || ok "open: missing session fails"
TM_TERMINAL="$WORK/bin/xfce4-terminal" q tm open oa
grep -qx -- '--window -x env -u TMUX -u TMUX_PANE tmux attach-session -t =oa' "$WORK/xfce4-terminal.log" \
  && ok "open: xfce4-terminal" || fail "open: xfce4-terminal wrong call"
TM_TERMINAL="$WORK/bin/xterm" q tm open oa
wait_for "[ -s '$WORK/xterm.log' ]"
grep -qx -- '-e env -u TMUX -u TMUX_PANE tmux attach-session -t =oa' "$WORK/xterm.log" \
  && ok "open: any other terminal gets -e COMMAND" || fail "open: generic terminal wrong call"
TM_TERMINAL=no-such-terminal q tm open oa && fail "open: a missing terminal should fail" || ok "open: missing terminal fails"
tmux kill-server 2>/dev/null

# --- kill-all asks first ----------------------------------------------------
q tm create keep
echo n | q tm kill-all
tmux has-session -t =keep 2>/dev/null && ok "kill-all: 'n' keeps everything" || fail "kill-all: killed without confirmation"
echo | q tm kill-all
tmux has-session -t =keep 2>/dev/null && ok "kill-all: Enter cancels" || fail "kill-all: Enter killed everything"
echo y | q tm kill-all
tmux has-session -t =keep 2>/dev/null && fail "kill-all: 'y' did not kill" || ok "kill-all: 'y' kills everything"

# --- conf: link, idempotent, never overwrites a backup ----------------------
q tm conf
[ "$(readlink -f "$HOME/.tmux.conf")" = "$REPO/tmux.conf" ] && ok "conf links tmux.conf" || fail "conf link wrong"
q tm conf
[ ! -e "$HOME/.tmux.conf.bak" ] && ok "conf is idempotent (no .bak)" || fail "conf made a .bak on 2nd run"
rm "$HOME/.tmux.conf"; echo mine > "$HOME/.tmux.conf"; echo old-backup > "$HOME/.tmux.conf.bak"
q tm conf
{ [ "$(cat "$HOME/.tmux.conf.bak")" = old-backup ] && [ "$(cat "$HOME"/.tmux.conf.bak.* 2>/dev/null)" = mine ]; } \
  && ok "conf: keeps the older .bak, saves the new one aside" || fail "conf: overwrote an older .bak"
rm -f "$HOME"/.tmux.conf.bak.*

# --- link: tm in ~/.local/bin, completions, old alias removed ---------------
printf '%s\n' "export FOO=1" "alias tm='make --no-print-directory -C \"/old/place\"'" "alias ll='ls -l'" > "$HOME/.bashrc"
q tm link; q tm link
[ "$(readlink -f "$HOME/.local/bin/tm")" = "$REPO/bin/tm" ] && ok "link: ~/.local/bin/tm points to the repo" || fail "link: tm not linked"
[ "$(readlink -f "$XDG_DATA_HOME/bash-completion/completions/tm")" = "$REPO/completions/tm.bash" ] \
  && ok "link: bash completion installed" || fail "link: bash completion missing"
{ ! grep -q "^alias tm=" "$HOME/.bashrc" && grep -q "^export FOO=1$" "$HOME/.bashrc" && grep -q "^alias ll=" "$HOME/.bashrc"; } \
  && ok "link: removes only the old make alias from ~/.bashrc" || fail "link: ~/.bashrc edited wrongly"
grep -q "^alias tm='make" "$HOME/.bashrc.tm-backup" && ok "link: ~/.bashrc backup kept" || fail "link: no ~/.bashrc backup"
echo "not mine" > "$WORK/other"; rm "$HOME/.local/bin/tm"; cp "$WORK/other" "$HOME/.local/bin/tm"
q tm link && fail "link: should refuse to replace a real file" || ok "link: leaves a foreign ~/.local/bin/tm alone"
rm "$HOME/.local/bin/tm"; q tm link

# --- completion -------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
q tm create "a b"; q tm create abc
comp() { bash -c 'source "$1"; shift; COMP_WORDS=("$@"); COMP_CWORD=$(( $# - 1 )); _tm; printf "%s\n" "${COMPREPLY[@]}"' _ "$REPO/completions/tm.bash" "$@"; }
[ "$(comp tm att)" = attach ] && ok "bash completion: commands" || fail "bash completion: commands ($(comp tm att))"
[ "$(comp tm kill a | sort | tr '\n' ' ')" = 'a\ b abc ' ] && ok "bash completion: session names, spaces escaped" || fail "bash completion: sessions ($(comp tm kill a | tr '\n' ' '))"
[ "$(comp tm open --a)" = --all ] && ok "bash completion: open --all" || fail "bash completion: open flags"
for s in bash zsh fish; do [ -n "$(tm completion $s)" ] || fail "completion $s printed nothing"; done
q tm completion tcsh && fail "completion: unknown shell should fail" || ok "completion: prints bash/zsh/fish, refuses others"
if command -v zsh >/dev/null; then check "zsh completion parses" zsh -n "$REPO/completions/_tm"; fi
if command -v fish >/dev/null; then check "fish completion parses" fish -n "$REPO/completions/tm.fish"; fi
tmux kill-server 2>/dev/null

# --- boot: a copy of the unit with this machine's tmux path ----------------
# systemctl/loginctl are stubbed: CI has no user systemd, and we only check what lands on disk.
printf '#!/bin/sh\nexit 0\n' | tee "$WORK/bin/systemctl" > "$WORK/bin/loginctl"
chmod +x "$WORK/bin/systemctl" "$WORK/bin/loginctl"
mkdir -p "$HOME/.tmux/plugins/tmux-resurrect"
unit="$HOME/.config/systemd/user/tmux.service"
mkdir -p "$(dirname "$unit")" && ln -s "$REPO/tmux.service" "$unit"   # an old install: a link to the repo
PATH="$WORK/bin:$PATH" q tm boot
{ [ -f "$unit" ] && [ ! -L "$unit" ] && grep -q "exec $(command -v tmux) new-session -d'$" "$unit" && ! grep -q @TMUX@ "$unit"; } \
  && ok "boot: unit is a plain copy with this tmux's path" || fail "boot: wrong unit"
[ "$(stat -c %a "$unit")" = 644 ] && ok "boot: unit is 644" || fail "boot: unit mode $(stat -c %a "$unit")"

# --- doctor -----------------------------------------------------------------
out=$(PATH="$WORK/bin:$PATH" tm doctor 2>&1)
{ echo "$out" | grep -q "ok    ~/.tmux.conf -> repo" && echo "$out" | grep -q "ok    ~/.local/bin/tm -> repo" \
  && echo "$out" | grep -q "FAIL  plugins not installed"; } \
  && ok "doctor: reports what is set up and what is not" || fail "doctor output: $out"
PATH="$WORK/bin:$PATH" q tm doctor && fail "doctor: should fail while something is wrong" || ok "doctor: exit status 1 on FAIL"

# --- uninstall undoes setup, keeps data -------------------------------------
echo old-conf > "$HOME/.tmux.conf.bak"
mkdir -p "$XDG_DATA_HOME/tmux/resurrect"; echo save > "$XDG_DATA_HOME/tmux/resurrect/last"
echo n | PATH="$WORK/bin:$PATH" q tm uninstall
[ -L "$HOME/.local/bin/tm" ] && ok "uninstall: 'n' cancels" || fail "uninstall: 'n' removed things"
echo y | PATH="$WORK/bin:$PATH" q tm uninstall
{ [ ! -e "$unit" ] && [ ! -e "$HOME/.local/bin/tm" ] && [ ! -e "$XDG_DATA_HOME/bash-completion/completions/tm" ] \
  && [ "$(cat "$HOME/.tmux.conf")" = old-conf ] && [ -f "$XDG_DATA_HOME/tmux/resurrect/last" ] && [ -d "$HOME/.tmux/plugins" ]; } \
  && ok "uninstall: removes unit and links, restores the old conf, keeps plugins and saves" || fail "uninstall: wrong result"
rm -rf "$HOME/.tmux" "$HOME/.tmux.conf" "$XDG_DATA_HOME/tmux"
q tm conf; q tm link

# --- update: pulls and runs the new version -------------------------------
if command -v git >/dev/null; then
  g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }
  mkdir -p "$WORK/up"
  cp -r "$REPO/bin" "$REPO/completions" "$REPO/tmux.conf" "$REPO/tmux.service" "$WORK/up/"
  q g -C "$WORK/up" init; q g -C "$WORK/up" add -A; q g -C "$WORK/up" commit -m one
  q g clone "$WORK/up" "$WORK/clone"
  echo "# new" >> "$WORK/up/tmux.conf"; q g -C "$WORK/up" commit -am two
  q "$WORK/clone/bin/tm" update
  [ "$(git -C "$WORK/clone" rev-parse HEAD)" = "$(git -C "$WORK/up" rev-parse HEAD)" ] && ok "update: pulls the repo" || fail "update: did not pull"
  echo "# local" >> "$WORK/clone/tmux.conf"; q g -C "$WORK/clone" commit -am local
  echo "# diverged" >> "$WORK/up/tmux.service"; q g -C "$WORK/up" commit -am three
  q "$WORK/clone/bin/tm" update && fail "update: a diverged repo should fail" || ok "update: refuses to merge (fast-forward only)"
fi

# --- save hook: claude panes get their own conversation, a missing folder is kept ------------
# A fake "claude" (not exec'd, so ps shows it as the pane's command) logs how it was started and,
# when $WORK/claude-id exists, writes the per-process file real claude keeps (~/.claude/sessions/PID.json).
mkdir -p "$WORK/fakebin" "$WORK/saves"
cat > "$WORK/fakebin/claude" <<EOS
#!/bin/sh
if [ -f "$WORK/claude-id" ]; then
  mkdir -p "\$HOME/.claude/sessions"
  printf '{"pid":%s,"sessionId":"%s","cwd":"/x"}' \$\$ "\$(cat "$WORK/claude-id")" > "\$HOME/.claude/sessions/\$\$.json"
fi
# Logged last: once the line is there, the session file is written too (the tests wait on it).
echo "args:\$*" >> "$WORK/claude.log"
sleep 600
EOS
chmod +x "$WORK/fakebin/claude"
tmux kill-server 2>/dev/null
id_a=aaaaaaaa-1111-2222-3333-444444444444
echo "$id_a" > "$WORK/claude-id"
tmux new-session -d -s c1 -c "$WORK"
tmux send-keys -t =c1: "PATH='$WORK/fakebin':\$PATH claude --continue --model x" Enter
wait_for "grep -qx 'args:--continue --model x' '$WORK/claude.log' 2>/dev/null" || fail "save hook: fake claude 1 did not start"
# An ID that is not a plain UUID is never written into the save (it is typed into a shell on restore).
echo "x; touch $WORK/pwned4" > "$WORK/claude-id"
tmux new-session -d -s c2 -c "$WORK"
tmux send-keys -t =c2: "PATH='$WORK/fakebin':\$PATH claude" Enter
wait_for "grep -qx 'args:' '$WORK/claude.log' 2>/dev/null" || fail "save hook: fake claude 2 did not start"
wait_for "[ \$(ls '$HOME/.claude/sessions' | wc -l) = 2 ]"
rm -f "$WORK/claude-id"
wi() { tmux display -p -t "=$1:" '#{window_index} #{pane_index}'; }
T=$'\t'
printf '%s\n' "pane${T}c3${T}1${T}1${T}:*${T}1${T}t${T}:$WORK/gone\\ dir${T}1${T}bash${T}:" \
  "pane${T}c4${T}1${T}1${T}:*${T}1${T}t${T}:$WORK/gone2${T}1${T}bash${T}:" \
  "pane${T}c5${T}1${T}1${T}:*${T}1${T}t${T}:$WORK${T}1${T}bash${T}:" > "$WORK/saves/old.txt"
ln -s old.txt "$WORK/saves/last"
read -r w1 p1 <<<"$(wi c1)"; read -r w2 p2 <<<"$(wi c2)"
printf '%s\n' "pane${T}c1${T}${w1}${T}1${T}:*${T}${p1}${T}${T}:$WORK${T}1${T}claude${T}:claude --continue --model x" \
  "pane${T}c2${T}${w2}${T}1${T}:*${T}${p2}${T}t${T}:$WORK${T}1${T}claude${T}:claude" \
  "pane${T}c3${T}1${T}1${T}:*${T}1${T}t${T}:$HOME${T}1${T}bash${T}:" \
  "pane${T}c4${T}1${T}1${T}:*${T}1${T}t${T}:$WORK${T}1${T}bash${T}:" \
  "pane${T}c5${T}1${T}1${T}:*${T}1${T}t${T}:$HOME${T}1${T}bash${T}:" \
  "pane${T}c6${T}1${T}1${T}:*${T}1${T}t${T}:$WORK${T}1${T}sh${T}:/bin/sh /opt/x/claude -c --resume=old" \
  "pane${T}c7${T}1${T}1${T}:*${T}1${T}t${T}:$WORK${T}1${T}vim${T}:vim claude" \
  "window${T}c1${T}1${T}:claude${T}1${T}:*${T}layout${T}:" "state${T}c1${T}" > "$WORK/saves/new.txt"
cp "$WORK/saves/new.txt" "$WORK/saves/orig.txt"
q tm _save-hook "$WORK/saves/new.txt"
line() { grep -P "^pane\t$1\t" "$WORK/saves/new.txt"; }
[ "$(line c1 | cut -f11)" = ":claude --model x --resume $id_a" ] && ok "save hook: claude saved as --resume ID, other args kept" \
  || fail "save hook: c1 is '$(line c1 | cut -f11)'"
[ "$(line c2 | cut -f11)" = ":claude --continue" ] && [ ! -e "$WORK/pwned4" ] \
  && ok "save hook: an ID that is not a UUID falls back to --continue" || fail "save hook: c2 is '$(line c2 | cut -f11)'"
[ "$(line c1 | cut -f7)" = "" ] && [ "$(line c1 | awk -F'\t' '{print NF}')" = 11 ] && ok "save hook: empty fields kept" || fail "save hook: fields shifted"
[ "$(line c3 | cut -f8)" = ":$WORK/gone\\ dir" ] && ok "save hook: a pane that fell back to ~ keeps its missing folder" \
  || fail "save hook: c3 folder is '$(line c3 | cut -f8)'"
[ "$(line c4 | cut -f8)" = ":$WORK" ] && ok "save hook: a real change of folder is saved" || fail "save hook: c4 folder is '$(line c4 | cut -f8)'"
[ "$(line c5 | cut -f8)" = ":$HOME" ] && ok "save hook: moving to ~ is saved when the old folder still exists" \
  || fail "save hook: c5 folder is '$(line c5 | cut -f8)'"
[ "$(line c6 | cut -f11)" = ":claude --resume=old" ] && ok "save hook: claude run by an interpreter; a --resume without a known ID is kept" \
  || fail "save hook: c6 is '$(line c6 | cut -f11)'"
[ "$(line c7 | cut -f11)" = ":vim claude" ] && ok "save hook: 'vim claude' is not a claude pane" || fail "save hook: c7 is '$(line c7 | cut -f11)'"
diff <(grep -v '^pane' "$WORK/saves/orig.txt") <(grep -v '^pane' "$WORK/saves/new.txt") >/dev/null \
  && ok "save hook: window and state lines untouched" || fail "save hook: changed other lines"
q tm _save-hook "$WORK/saves/missing.txt" && ok "save hook: a missing file is a no-op" || fail "save hook: failed on a missing file"
tmux kill-server 2>/dev/null
: > "$WORK/claude.log"; rm -rf "$HOME/.claude"

# --- ls shows the folder, create warns about ~ ------------------------------
mkdir -p "$WORK/lsdir"
q tm create lsd "$WORK/lsdir"
tm ls | grep -q "lsd: 1 window(s), free, $WORK/lsdir$" && ok "ls: shows each session's folder" || fail "ls: $(tm ls)"
out=$(cd "$HOME" && tm create inhome 2>&1)
echo "$out" | grep -q "starts in ~" && ok "create without DIR in ~: warns" || fail "create in ~: no warning ($out)"
tm ls | grep -q "inhome: .*, ~$" && ok "ls: shows ~ for the home folder" || fail "ls: home not shown as ~"
out=$(cd "$WORK" && tm create elsewhere 2>&1)
echo "$out" | grep -q "starts in ~" && fail "create outside ~: warned anyway" || ok "create without DIR outside ~: no warning"
tmux kill-server 2>/dev/null

# --- tmux.conf ---------------------------------------------------------------
grep -q "^set -g @continuum-boot 'on'" "$REPO/tmux.conf" \
  && ok "tmux.conf sets @continuum-boot on" || fail "tmux.conf lost @continuum-boot on"
cfg_err=$(tmux -L cfgcheck -f /dev/null new-session -d \; source-file "$REPO/tmux.conf" 2>&1)
cfg_rc=$?
[ "$cfg_rc" = 0 ] && [ -z "$cfg_err" ] && ok "tmux.conf loads on $(tmux -V)" || fail "tmux.conf errors on $(tmux -V): $cfg_err"
[ "$(tmux -L cfgcheck show -gv base-index)" = 1 ] && ok "tmux.conf: windows start at 1" || fail "tmux.conf: base-index not 1"
tmux -L cfgcheck kill-server 2>/dev/null
# The per-machine file is loaded.
echo "set -g @tm-local-test yes" > "$HOME/.tmux.local.conf"
tmux -L cfgcheck -f "$REPO/tmux.conf" new-session -d
[ "$(tmux -L cfgcheck show -gv @tm-local-test 2>/dev/null)" = yes ] && ok "tmux.conf loads ~/.tmux.local.conf" || fail "\$HOME/.tmux.local.conf not loaded"
tmux -L cfgcheck kill-server 2>/dev/null
rm "$HOME/.tmux.local.conf"

# --- network: plugins, pinned commits, save and restore ---------------------
if [ "${RUN_NETWORK:-0}" = 1 ]; then
  q tm plugins && ok "plugins install" || fail "plugins install"
  for p in "tpm TPM" "tmux-resurrect RESURRECT" "tmux-continuum CONTINUUM"; do
    read -r dir var <<<"$p"
    want=$(sed -n "s/^${var}_SHA=//p" "$REPO/bin/tm")
    got=$(git -C "$HOME/.tmux/plugins/$dir" rev-parse HEAD 2>/dev/null)
    [ -n "$want" ] && [ "$want" = "$got" ] && ok "$dir pinned to $want" || fail "$dir not on pinned commit"
  done
  [ "$(stat -c %a "$XDG_DATA_HOME/tmux/resurrect")" = 700 ] && ok "resurrect dir is 700" || fail "resurrect dir not 700"
  out=$(PATH="$WORK/bin:$PATH" tm doctor 2>&1)
  echo "$out" | grep -q "ok    plugins on the pinned commits" && ok "doctor: plugins ok after tm plugins" || fail "doctor after plugins: $out"

  # The fake "claude" from the save hook tests, without an ID file first: saved and relaunched as --continue.
  # The boot service's own commands, run with no locale at all (as under a systemd without LANG):
  # tmux then prints tabs as "_" and resurrect used to write empty saves. %h and $$ as systemd expands them.
  unit_cmd() { tm _unit | sed -n "s/^$1=//p" | sed "s|%h|$HOME|g; s/\$\$/\$/g"; }
  nolocale() { env -u LANG -u LC_ALL -u LC_CTYPE PATH="$WORK/fakebin:$PATH" "$@"; }
  saved() { grep -qP "^pane\twork\t" "$XDG_DATA_HOME/tmux/resurrect/last" 2>/dev/null; }
  # continuum skips the restore when any other tmux process is around (it counts them),
  # so a server that is still exiting would make a restore test flaky: wait for it to be gone.
  no_tmux() { tmux kill-server 2>/dev/null; wait_for "! pgrep -u $(id -u) '^tmux' >/dev/null"; }
  no_tmux
  nolocale sh -c "$(unit_cmd ExecStart)"
  tmux rename-session -t =0 work && tmux send-keys -t =work: "cd '$WORK' && claude" Enter
  wait_for "grep -qx 'args:' '$WORK/claude.log' 2>/dev/null" || fail "fake claude did not start"
  nolocale sh -c "$(unit_cmd ExecStop)"
  saved && ok "boot service save (ExecStop) works without a locale" || fail "ExecStop wrote an empty save"
  tmux kill-server 2>/dev/null
  # The boot service start: a bare server, continuum restores the save into it.
  nolocale sh -c "$(unit_cmd ExecStart)"
  wait_for "tmux has-session -t =work 2>/dev/null" && ok "restore at server start (continuum, no locale)" || fail "work not restored at start"
  wait_for "grep -qx 'args:--continue' '$WORK/claude.log'" && ok "restore: claude relaunched as 'claude --continue'" \
    || fail "claude not relaunched with --continue: $(tr '\n' '|' < "$WORK/claude.log")"
  { tmux has-session -t =work 2>/dev/null && wait_for "! tmux has-session -t =0 2>/dev/null"; } \
    && ok "restore: the boot service's unnamed session is removed" || fail "session 0 left behind"
  # With the ID file claude keeps per process, the save has "--resume ID" and that is what comes back.
  id_b=bbbbbbbb-1111-2222-3333-444444444444
  echo "$id_b" > "$WORK/claude-id"
  tmux respawn-pane -k -t =work: -c "$WORK"
  tmux send-keys -t =work: "PATH='$WORK/fakebin':\$PATH claude" Enter
  wait_for "[ -n \"\$(ls '$HOME/.claude/sessions' 2>/dev/null)\" ]" || fail "fake claude wrote no session file"
  rm -f "$WORK/claude-id"
  nolocale sh -c "$(unit_cmd ExecStop)"
  grep -qP "^pane\twork\t.*\t:claude --resume $id_b$" "$XDG_DATA_HOME/tmux/resurrect/last" \
    && ok "save (resurrect + hook): claude saved as --resume ID" || fail "save: $(grep -P '^pane' "$XDG_DATA_HOME/tmux/resurrect/last")"
  no_tmux
  nolocale sh -c "$(unit_cmd ExecStart)"
  wait_for "grep -qx 'args:--resume $id_b' '$WORK/claude.log'" && ok "restore: claude relaunched with its own conversation (--resume ID)" \
    || fail "claude not relaunched with --resume: $(tr '\n' '|' < "$WORK/claude.log")"
  wait_for "! tmux has-session -t =0 2>/dev/null"
  rm -f "$XDG_DATA_HOME/tmux/resurrect/last"
  nolocale "$REPO/bin/tm" save >/dev/null 2>&1; saved && ok "tm save works without a locale" || fail "tm save wrote an empty save"
  no_tmux; nolocale "$REPO/bin/tm" restore >/dev/null 2>&1
  wait_for "tmux has-session -t =work 2>/dev/null" && ok "tm restore: brings back a killed session" || fail "tm restore failed"
  tmux kill-server 2>/dev/null
fi

echo
[ "$fails" = 0 ] && echo "all passed" || echo "$fails failed"
# Not "exit $fails": 256 failures would wrap around to 0 (success).
exit $(( fails > 0 ))

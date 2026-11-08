#!/usr/bin/env bash
# Lint, same as CI: shellcheck on every shell file, markdownlint on the docs, and the systemd unit. "make lint".
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v docker >/dev/null || { echo "docker is not installed."; exit 1; }

SHELLCHECK=koalaman/shellcheck@sha256:bb596a0d169b85ddd81d8b6d3a2ff6d5baf5fca10b97f575ebc647c3dff62b3d
MARKDOWNLINT=davidanson/markdownlint-cli2@sha256:70ead7c0352d22d04bbe612cd96b54ec591538d8f4626cafe391bb2ecf3639ca

echo "== shellcheck =="
docker run --rm -v "$REPO:/repo:ro" -w /repo "$SHELLCHECK" bin/tm completions/tm.bash tests/*.sh
echo "No issues."

echo "== markdownlint =="
docker run --rm -v "$REPO:/workdir:ro" "$MARKDOWNLINT" "*.md"

# zsh and fish completions: syntax check only when those shells are here (shellcheck does not read them).
if command -v zsh >/dev/null; then echo "== zsh -n =="; zsh -n "$REPO/completions/_tm" && echo "No issues."; fi
if command -v fish >/dev/null; then echo "== fish -n =="; fish -n "$REPO/completions/tm.fish" && echo "No issues."; fi

# The unit as "tm boot" installs it. systemd-analyze checks that ExecStop exists, under this user's home.
if command -v systemd-analyze >/dev/null; then
  echo "== systemd-analyze verify =="
  dir=$(mktemp -d)
  trap 'rm -f "$dir/tmux.service"; rmdir "$dir"' EXIT
  "$REPO/bin/tm" _unit > "$dir/tmux.service"
  if [ -x "$HOME/.tmux/plugins/tmux-resurrect/scripts/save.sh" ]; then
    systemd-analyze verify --user "$dir/tmux.service" && echo "No issues."
  else
    echo "Skipped: tmux-resurrect is not installed here (CI installs a stub first)."
  fi
fi

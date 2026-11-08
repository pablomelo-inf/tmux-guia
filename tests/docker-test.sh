#!/usr/bin/env bash
# Runs tests/test.sh in clean Ubuntu containers, as CI does. "make docker-test".
# UBUNTU=24.04 runs one version; RUN_NETWORK=1 is passed through.
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v docker >/dev/null || { echo "docker is not installed."; exit 1; }

for v in ${UBUNTU:-22.04 24.04}; do
  echo "== Ubuntu $v =="
  docker build -q --build-arg UBUNTU="$v" -t "tmux-guia-test:$v" -f "$REPO/tests/Dockerfile" "$REPO/tests" >/dev/null
  # Read-only mount: a test that writes to the repo fails.
  docker run --rm -e RUN_NETWORK="${RUN_NETWORK:-0}" -v "$REPO:/repo:ro" "tmux-guia-test:$v"
done

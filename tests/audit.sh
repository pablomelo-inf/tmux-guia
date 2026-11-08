#!/usr/bin/env bash
# Security checks, same as CI: secrets, GitHub Actions, Dockerfile, CVEs in the test images. "make audit".
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v docker >/dev/null || { echo "docker is not installed."; exit 1; }

# Scanners pinned by digest (a tag can be moved to other content). To update: pull the new release, check it, change the digest.
GITLEAKS=zricethezav/gitleaks@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f
ZIZMOR=ghcr.io/zizmorcore/zizmor@sha256:3014cc8f68f663935f69b3c3e0e41f5ce102b268d97db13db0f62208747f860d
HADOLINT=hadolint/hadolint@sha256:32dac94127fd60b7b7e3fbfc65e1383b9b5e25c9bfd7b8536de7a539fe68a12d
TRIVY=aquasec/trivy@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb
CACHE=tmux-guia-trivy-cache

echo "== gitleaks: secrets in the git history =="
docker run --rm -v "$REPO:/repo:ro" "$GITLEAKS" git /repo --no-banner --redact

echo "== zizmor: GitHub Actions and Dependabot config =="
docker run --rm -v "$REPO:/repo:ro" "$ZIZMOR" --offline /repo/.github

echo "== hadolint: tests/Dockerfile =="
docker run --rm -i "$HADOLINT" hadolint --failure-threshold info - < "$REPO/tests/Dockerfile"
echo "No issues."

echo "== trivy: secrets and misconfigurations in the repo =="
docker run --rm -v "$REPO:/repo:ro" -v "$CACHE:/root/.cache" "$TRIVY" fs --quiet --exit-code 1 \
  --scanners secret,misconfig --ignorefile /repo/.trivyignore /repo

for v in ${UBUNTU:-22.04 24.04}; do
  echo "== trivy: fixable HIGH/CRITICAL CVEs in the Ubuntu $v test image =="
  docker build -q --build-arg UBUNTU="$v" -t "tmux-guia-test:$v" -f "$REPO/tests/Dockerfile" "$REPO/tests" >/dev/null
  # The image is piped in as a tar and kept inside the throwaway scanner container.
  # Mounting the Docker socket instead would give the scanner control of Docker.
  # shellcheck disable=SC2016 # expanded by the container's sh, not here
  docker save "tmux-guia-test:$v" | docker run --rm -i -v "$CACHE:/root/.cache" --entrypoint sh "$TRIVY" \
    -c 'cat > /tmp/img.tar && trivy image --quiet --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed --input /tmp/img.tar'
done
echo "Audit passed."

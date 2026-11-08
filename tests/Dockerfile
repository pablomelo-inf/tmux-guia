# Clean Ubuntu to run tests/test.sh, same as CI. Used by "make docker-test" and scanned by "make audit".
# UBUNTU picks the tmux version: 22.04 has 3.2a (the oldest supported), 24.04 has 3.4.
# Base images are pinned by digest (a tag can be moved to other content); Dependabot bumps them.
ARG UBUNTU=24.04
FROM ubuntu:22.04@sha256:076e7bf82319619f28dd0aa9c02ab34b055ad37100395b4f49a2ffba04fb5e11 AS base-22.04
FROM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852 AS base-24.04
# hadolint ignore=DL3006
FROM base-${UBUNTU}

# upgrade: security fixes released after the pinned digest (the audit fails on fixable HIGH/CRITICAL CVEs).
# script (bsdutils) gives the test client a terminal; procps is how resurrect sees each pane's command;
# git + certificates are for RUN_NETWORK=1; zsh and fish check their completions.
# Versions are not pinned: they differ per Ubuntu release and old ones leave the archive.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends tmux make git ca-certificates bsdutils procps zsh fish \
 && rm -rf /var/lib/apt/lists/*

# Non-root, like a real user. The repo is mounted read-only at /repo, so a test that writes to it fails.
RUN useradd -m -u 10001 tester
USER 10001
ENV TERM=xterm-256color
WORKDIR /repo
CMD ["tests/test.sh"]

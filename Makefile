# Dev tasks for this repo. The session commands live in bin/tm ("bin/tm help"); "make setup" installs it.

.DEFAULT_GOAL := help
DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
.PHONY: help setup test docker-test audit lint

help:
	@echo "make setup        Install everything: tmux, config, the tm command, plugins, boot service"
	@echo "make test         Run the tests here (throwaway HOME and tmux socket). RUN_NETWORK=1 also installs plugins"
	@echo "make docker-test  Run the tests in clean Ubuntu 22.04 and 24.04 containers (UBUNTU=24.04 for one)"
	@echo "make audit        Security checks, same as CI (secrets, Actions, Dockerfile, CVEs)"
	@echo "make lint         shellcheck, markdownlint and the systemd unit, same as CI"
	@echo "Session commands: bin/tm help (after setup, just: tm help)"

setup:
	@"$(DIR)/bin/tm" setup

test:
	@"$(DIR)/tests/test.sh"

docker-test:
	@"$(DIR)/tests/docker-test.sh"

audit:
	@"$(DIR)/tests/audit.sh"

lint:
	@"$(DIR)/tests/lint.sh"

# Older versions had a "tm" alias that ran make with the command as a target ("tm attach work").
# Those calls land here: point to the new tm once, instead of a cryptic "No rule to make target".
.DEFAULT:
	@echo "\"$@\" is now a command of bin/tm. Run once: make -C \"$(DIR)\" setup  (or: \"$(DIR)/bin/tm\" link)"
	@echo "Then open a new terminal and use: tm $@ ..."
	@exit 1

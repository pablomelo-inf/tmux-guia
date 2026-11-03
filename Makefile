# tmux shortcuts. Run "make" (or "tm") to see the help.
# Commands that use a session take its name right after: tm attach home

.DEFAULT_GOAL := help

# Every target documented with "##" is a command (single source: the targets below).
COMMANDS := $(shell sed -n 's/^\([a-z-]*\):.*\#\# .*/\1/p' $(MAKEFILE_LIST))
.PHONY: $(COMMANDS)

# Audited plugin commits (they run code on every tmux start). To update: review the upstream diff, then change them here.
TPM_SHA := e261deb1b47614eed3400089ce7197dc68acc4eb
RESURRECT_SHA := cff343cf9e81983d3da0c8562b01616f12e8d548
CONTINUUM_SHA := 0698e8f4b17d6454c71bf5212895ec055c578da0

# Folder of this Makefile (where tmux.conf lives)
DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# Words after the command are arguments, not targets: tm rename OLD NEW
ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
NAME := $(or $(S),$(word 1,$(ARGS)))
NOVO := $(or $(N),$(word 2,$(ARGS)))
# Passed to the shell as environment variables (quoted in the recipes): a name with ; or $() is never run as a command.
export NAME NOVO

ifneq ($(ARGS),)
# A name equal to a command (tm kill clean) would also run that command: refuse it.
ifneq ($(filter $(COMMANDS),$(ARGS)),)
$(error "$(filter $(COMMANDS),$(ARGS))" is also a command name. Pass it with S=/N= instead, e.g.: tm kill S=clean)
endif
$(ARGS):
	@:
endif

B := $(shell tput bold 2>/dev/null)
R := $(shell tput sgr0 2>/dev/null)

check = @command -v tmux >/dev/null || { echo "tmux is not installed. Run: make install"; exit 1; }
need = @test -n "$$NAME" || { echo "Give a session name. E.g.: tm $@ name"; echo "Existing sessions:"; $(MAKE) --no-print-directory ls; exit 1; }

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / { printf "  $(B)%-9s$(R) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo "Example: tm attach home"
	@echo "To leave tmux without ending the session: Ctrl+b, release, d (never 'exit')."

ls: ## List sessions and whether they are in use
	$(check)
	@tmux ls -F '  #{session_name}: #{session_windows} window(s), #{?session_attached,in use,free}' 2>/dev/null \
	  || echo "No sessions running."

attach: ## Attach to a session, creating it if missing: tm attach NAME
	$(check)
	$(need)
	@tmux new-session -A -s "$$NAME"

create: ## Create a session without attaching: tm create NAME
	$(check)
	$(need)
	@tmux new-session -d -s "$$NAME" && echo "Session '$$NAME' created. To attach: tm attach $$NAME"

detach: ## Detach clients, keep the session running: tm detach NAME
	$(check)
	$(need)
	@tmux detach-client -s "$$NAME" && echo "Session '$$NAME' detached, still running."

rename: ## Rename a session: tm rename OLD NEW
	$(check)
	$(need)
	@test -n "$$NOVO" || { echo "Missing the new name. E.g.: tm rename $$NAME other"; exit 1; }
	@tmux rename-session -t "$$NAME" "$$NOVO" && echo "'$$NAME' is now called '$$NOVO'."

kill: ## Kill a session (whatever ran in it is lost): tm kill NAME
	$(check)
	$(need)
	@tmux kill-session -t "$$NAME" && echo "Session '$$NAME' killed."

clean: ## Kill all free sessions; keep the ones in use
	$(check)
	@n=0; for s in $$(tmux ls -F '#{session_name} #{session_attached}' 2>/dev/null | awk '$$2==0 {print $$1}'); do \
	  tmux kill-session -t "$$s" && echo "killed: $$s" && n=$$((n+1)); \
	done; echo "$$n session(s) killed."

kill-all: ## Kill every session, even those in use (asks first)
	$(check)
	@read -p "Kill ALL sessions? [y/N] " r; \
	  if [ "$$r" = "y" ]; then tmux kill-server && echo "Everything killed."; else echo "Cancelled."; fi

install: ## Install tmux
	sudo apt install -y tmux

conf: ## Link this repo's tmux.conf to ~/.tmux.conf (backs up an existing one)
	@dst=$$HOME/.tmux.conf; \
	if [ "$$(readlink -f "$$dst")" = "$(DIR)/tmux.conf" ]; then echo "~/.tmux.conf already points to the repo."; exit 0; fi; \
	if [ -e "$$dst" ] || [ -L "$$dst" ]; then bak=$$dst.bak; [ -e "$$bak" ] && bak=$$bak.$$(date +%s); \
	  mv "$$dst" "$$bak" && echo "Backup: $$bak"; fi; \
	ln -s "$(DIR)/tmux.conf" "$$dst" && echo "Linked: ~/.tmux.conf -> $(DIR)/tmux.conf (applies to new sessions)."

alias: ## Add the "tm" alias to ~/.bashrc if missing
	@if grep -q "^alias tm=" $$HOME/.bashrc 2>/dev/null; then echo "Alias 'tm' already exists in ~/.bashrc."; else \
	  echo "alias tm='make --no-print-directory -C \"$(DIR)\"'" >> $$HOME/.bashrc; \
	  echo "Alias added. Run: source ~/.bashrc"; fi

plugins: ## Install TPM and the tmux.conf plugins (resurrect, continuum)
	$(check)
	@test -d $$HOME/.tmux/plugins/tpm || git clone -q https://github.com/tmux-plugins/tpm $$HOME/.tmux/plugins/tpm
	@# TPM runs on the next step, so pin it first: nothing from GitHub HEAD gets executed.
	@git -C $$HOME/.tmux/plugins/tpm checkout -q $(TPM_SHA)
	@# TPM reads the plugin path from the tmux server: make sure one is running and reload the config.
	@started=0; tmux has-session 2>/dev/null || { tmux new-session -d -s _tpm && started=1; }; \
	  tmux source-file $$HOME/.tmux.conf; \
	  $$HOME/.tmux/plugins/tpm/bin/install_plugins; rc=$$?; \
	  if [ $$started = 1 ]; then tmux kill-session -t _tpm; fi; exit $$rc
	@# Plugins stay on the commits pinned above, not on whatever is at GitHub HEAD.
	@P=$$HOME/.tmux/plugins; \
	  git -C $$P/tpm checkout -q $(TPM_SHA) && git -C $$P/tmux-resurrect checkout -q $(RESURRECT_SHA) \
	  && git -C $$P/tmux-continuum checkout -q $(CONTINUUM_SHA) || { echo "Failed to pin the plugin commits."; exit 1; }
	@# resurrect stores pane contents as plain text: only the owner may read it.
	@mkdir -p $$HOME/.local/share/tmux/resurrect && chmod 700 $$HOME/.local/share/tmux/resurrect
	@echo "Plugins installed. In open sessions run: tmux source ~/.tmux.conf"

boot: ## Start tmux at login (restores saved sessions, saves on shutdown)
	$(check)
	@test -d $$HOME/.tmux/plugins/tmux-resurrect || { echo "Run first: tm plugins"; exit 1; }
	@# A copy, not a link: the service keeps working if this repo is moved or deleted. Re-run to update it.
	@unit=$$HOME/.config/systemd/user/tmux.service; \
	  mkdir -p "$$(dirname "$$unit")" && rm -f "$$unit" && install -m 644 "$(DIR)/tmux.service" "$$unit" \
	  && systemctl --user daemon-reload && systemctl --user reenable tmux.service
	@echo "Enabled for the next login. To start it now: systemctl --user start tmux"
	@# Without linger, systemd stops the user's services when the last session ends.
	@loginctl show-user "$$USER" -p Linger 2>/dev/null | grep -q yes \
	  || echo "Tip: for tmux to survive the last logout (e.g. an SSH drop), run: loginctl enable-linger"
	@echo "Open sessions:"
	@$(MAKE) --no-print-directory ls

setup: ## Do everything: tmux, config, alias, plugins and boot
	@command -v tmux >/dev/null || $(MAKE) --no-print-directory install
	@for t in conf alias plugins boot; do $(MAKE) --no-print-directory $$t || exit 1; done
	@echo "Done. Open a new terminal (or: source ~/.bashrc) and use: tm attach NAME"

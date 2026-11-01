# Atalhos para o tmux. Rode "make" (ou "tm") para ver a ajuda.
# Os comandos que usam uma sessão recebem o nome logo depois: tm attach casa

.DEFAULT_GOAL := help
.PHONY: help ls attach create detach rename kill clean kill-all install conf alias plugins boot setup

# Pasta deste Makefile (onde fica o tmux.conf)
DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# Nome da sessão: o 2º argumento (tm attach casa) ou S=casa
NAME := $(or $(S),$(word 2,$(MAKECMDGOALS)))
NOVO := $(or $(N),$(word 3,$(MAKECMDGOALS)))

# Os argumentos extras (casa, novo...) não são comandos: ignora-os.
ifneq ($(words $(MAKECMDGOALS)),1)
$(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS)):
	@:
endif

B := $(shell tput bold 2>/dev/null)
R := $(shell tput sgr0 2>/dev/null)

check = @command -v tmux >/dev/null || { echo "tmux não está instalado. Rode: make install"; exit 1; }
need = @test -n "$(NAME)" || { echo "Informe a sessão. Ex.: tm $@ nome"; echo "Sessões existentes:"; $(MAKE) --no-print-directory ls; exit 1; }

help: ## Mostra esta ajuda
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / { printf "  $(B)%-9s$(R) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo "Exemplo: tm attach casa"
	@echo "Para sair do tmux sem encerrar a sessão: Ctrl+b, soltar, d (nunca 'exit')."

ls: ## Lista as sessões e diz se estão em uso
	$(check)
	@tmux ls -F '  #{session_name}: #{session_windows} janela(s), #{?session_attached,em uso,livre}' 2>/dev/null \
	  || echo "Nenhuma sessão rodando."

attach: ## Entra na sessão: tm attach NOME (cria se não existir)
	$(check)
	$(need)
	@tmux new-session -A -s $(NAME)

create: ## Cria a sessão sem entrar: tm create NOME
	$(check)
	$(need)
	@tmux new-session -d -s $(NAME) && echo "Sessão '$(NAME)' criada. Para entrar: tm attach $(NAME)"

detach: ## Desconecta quem está na sessão, mantendo ela rodando: tm detach NOME
	$(check)
	$(need)
	@tmux detach-client -s $(NAME) && echo "Sessão '$(NAME)' desconectada, continua rodando."

rename: ## Renomeia a sessão: tm rename ANTIGO NOVO
	$(check)
	$(need)
	@test -n "$(NOVO)" || { echo "Faltou o novo nome. Ex.: tm rename $(NAME) outro"; exit 1; }
	@tmux rename-session -t $(NAME) $(NOVO) && echo "'$(NAME)' agora se chama '$(NOVO)'."

kill: ## Encerra a sessão (o que rodava nela é perdido): tm kill NOME
	$(check)
	$(need)
	@tmux kill-session -t $(NAME) && echo "Sessão '$(NAME)' encerrada."

clean: ## Encerra todas as sessões livres; mantém as em uso
	$(check)
	@n=0; for s in $$(tmux ls -F '#{session_name} #{session_attached}' 2>/dev/null | awk '$$2==0 {print $$1}'); do \
	  tmux kill-session -t "$$s" && echo "encerrada: $$s" && n=$$((n+1)); \
	done; echo "$$n sessão(ões) encerrada(s)."

kill-all: ## Encerra todas as sessões, inclusive as em uso (pede confirmação)
	$(check)
	@read -p "Encerrar TODAS as sessões? [s/N] " r; \
	  if [ "$$r" = "s" ]; then tmux kill-server && echo "Tudo encerrado."; else echo "Cancelado."; fi

install: ## Instala o tmux
	sudo apt install -y tmux

conf: ## Linka o tmux.conf deste repo em ~/.tmux.conf (faz backup do existente)
	@dst=$$HOME/.tmux.conf; \
	if [ "$$(readlink -f $$dst)" = "$(DIR)/tmux.conf" ]; then echo "~/.tmux.conf já aponta para o repo."; exit 0; fi; \
	if [ -e $$dst ] || [ -L $$dst ]; then mv $$dst $$dst.bak && echo "Backup: $$dst.bak"; fi; \
	ln -s $(DIR)/tmux.conf $$dst && echo "Linkado: ~/.tmux.conf -> $(DIR)/tmux.conf (vale para sessões novas)."

alias: ## Adiciona o alias "tm" ao ~/.bashrc, se ainda não existir
	@if grep -q "^alias tm=" $$HOME/.bashrc 2>/dev/null; then echo "Alias 'tm' já existe no ~/.bashrc."; else \
	  echo "alias tm='make --no-print-directory -C $(DIR)'" >> $$HOME/.bashrc; \
	  echo "Alias adicionado. Rode: source ~/.bashrc"; fi

plugins: ## Instala o TPM e os plugins (resurrect, continuum) do tmux.conf
	$(check)
	@test -d $$HOME/.tmux/plugins/tpm || git clone -q https://github.com/tmux-plugins/tpm $$HOME/.tmux/plugins/tpm
	@# O TPM lê o caminho dos plugins do servidor tmux: garante um servidor e recarrega a config.
	@started=0; tmux has-session 2>/dev/null || { tmux new-session -d -s _tpm && started=1; }; \
	  tmux source-file $$HOME/.tmux.conf; \
	  $$HOME/.tmux/plugins/tpm/bin/install_plugins; rc=$$?; \
	  if [ $$started = 1 ]; then tmux kill-session -t _tpm; fi; exit $$rc
	@echo "Plugins instalados. Em sessões abertas: tmux source ~/.tmux.conf"

boot: ## Sobe o tmux no login (restaura as sessões salvas e salva ao desligar)
	$(check)
	@test -d $$HOME/.tmux/plugins/tmux-resurrect || { echo "Rode antes: tm plugins"; exit 1; }
	@systemctl --user enable $(DIR)/tmux.service
	@echo "Ativo no próximo login. Para subir agora: systemctl --user start tmux"

setup: ## Faz tudo de uma vez: tmux, config, alias, plugins e boot
	@command -v tmux >/dev/null || $(MAKE) --no-print-directory install
	@for t in conf alias plugins boot; do $(MAKE) --no-print-directory $$t || exit 1; done
	@echo "Pronto. Abra um novo terminal (ou: source ~/.bashrc) e use: tm attach NOME"

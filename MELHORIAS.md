# Melhorias: estado

Feito na 2.0.0 (ver `CHANGELOG.md`): bugs 1.1 a 1.3 e 1.5, comandos novos, ajustes do `tmux.conf`, migração para `bin/tm`, testes em container, auditoria de segurança, lint.

O item 1.4 (sessão `0` extra no boot) não era bug: o resurrect a remove no restore (testado).

## Pendente

- Teste de boot com systemd real (container com systemd como PID 1).
- GIF de demonstração no README.
- Tags de versão no git.
- Teste de rede `tm restore` intermitente (cerca de 1 em 8, já existia na 2.0.0): o tmux-continuum só restaura se não houver outro processo tmux, e o laço de espera de `cmd_restore` (`tmux has-session` a cada 0,1 s) pode ser contado como "outro servidor".

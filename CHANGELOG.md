# Changelog

## 2.0.0

- `tm` is now a script (`bin/tm`) linked into `~/.local/bin`; the Makefile only keeps dev tasks. Run `make setup` once to migrate from the alias.
- Fixed: `clean`/`open` mishandled names with spaces; targets matched by prefix (`tm kill pro` could kill `projeto`); `attach` inside tmux nested a client.
- Fixed: without a UTF-8 locale tmux-resurrect wrote empty saves.
- New commands: `pick`, `save`, `restore`, `update`, `doctor`, `uninstall`, `link`, `completion`; `open` takes names, `--all` and more terminals; `attach`/`create` take a DIR.
- tmux.conf: windows from 1, splits in the current folder, `Ctrl+b r`, escape-time, true color, OSC 52, local overrides.
- Boot unit gets this machine's tmux path.
- Tests in Ubuntu 22.04/24.04 containers; security audit in CI; shellcheck on all code.

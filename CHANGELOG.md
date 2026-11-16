# Changelog

## 2.1.4

- Fixed: `tm restore` with no server at times restored nothing. tmux-continuum skips its restore when it counts another tmux process at the server start, and the `tmux` commands `tm restore` ran while waiting for it were that process. It now waits without running tmux, and restores by itself if continuum skipped.

## 2.1.3

- Fixed: a claude pane came back as a bare shell after a reboot when claude died before the shutdown save. tmux-resurrect saved its command as `[claude] <defunct>`, which the save hook did not take for claude. The hook now gives such a pane the previous save's command (with its `--resume ID`), or `claude --continue` when there is none.

## 2.1.2

- Fixed: when the tmux server died by itself (crash, OOM, `tmux kill-server`), systemd ran the boot service's stop save with no server; tmux-resurrect wrote an empty save and pointed `last` at it, so the next boot restored nothing. The save now runs only while a server is up. Run `tm boot` (or `tm update`) to install the new unit.

## 2.1.1

- Fixed: a pane with an empty title (claude leaves it so at times) came back in `~` with a bare shell after a reboot. tmux-resurrect reads its save with `IFS=tab`, bash merges runs of tabs, and the empty field shifted the rest of the line (folder saved as `1`, command lost). The save hook puts the fields back, gets the command from the pane's PID and gives the pane a title, since the restore reads the file the same way.

## 2.1.0

- Fixed: after a reboot, `claude` panes could open another session's conversation (`--continue` picks the newest one in the folder, the same for every session in it, often `~`). Each save now records `claude --resume ID` per pane (`tm _save-hook`, a tmux-resurrect hook).
- Fixed: a pane whose folder was missing at boot (disk not mounted yet) fell back to `~`, and the next save lost the real folder. The hook keeps it.
- `tm ls` shows each session's folder; `tm attach`/`create` without a DIR warn when the session would start in `~`.

## 2.0.0

- `tm` is now a script (`bin/tm`) linked into `~/.local/bin`; the Makefile only keeps dev tasks. Run `make setup` once to migrate from the alias.
- Fixed: `clean`/`open` mishandled names with spaces; targets matched by prefix (`tm kill pro` could kill `projeto`); `attach` inside tmux nested a client.
- Fixed: without a UTF-8 locale tmux-resurrect wrote empty saves.
- New commands: `pick`, `save`, `restore`, `update`, `doctor`, `uninstall`, `link`, `completion`; `open` takes names, `--all` and more terminals; `attach`/`create` take a DIR.
- tmux.conf: windows from 1, splits in the current folder, `Ctrl+b r`, escape-time, true color, OSC 52, local overrides.
- Boot unit gets this machine's tmux path.
- Tests in Ubuntu 22.04/24.04 containers; security audit in CI; shellcheck on all code.

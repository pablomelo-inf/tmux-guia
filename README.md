# tmux-guia

My tmux config plus a Makefile of session shortcuts (`tm`). Keeps terminals alive across SSH drops and lets you attach to the same session from any machine.

## Setup (Ubuntu)

```sh
sudo apt install -y git make
git clone git@github.com:pablomelo-inf/tmux-guia.git ~/tmux-guia
cd ~/tmux-guia
make setup     # installs tmux if missing, links tmux.conf, adds alias, installs plugins, enables boot service
```

Clone to `~/tmux-guia`: the alias points there. Without an SSH key on GitHub, clone via `https://github.com/pablomelo-inf/tmux-guia.git` instead.

## Updating

Edit `tmux.conf`, commit, push. On the other machine: `git pull`, then `tmux source ~/.tmux.conf` to reload without closing sessions.

## Commands

Session commands need the name right after: `tm attach work`.

| Command | Does |
|---|---|
| `tm ls` | List sessions (in use / free) |
| `tm attach NAME` | Attach, creating the session if missing |
| `tm create NAME` | Create detached |
| `tm detach NAME` | Detach clients, keep session running |
| `tm rename OLD NEW` | Rename |
| `tm kill NAME` | Kill session |
| `tm clean` | Kill all free sessions |
| `tm kill-all` | Kill everything (asks first) |
| `tm setup` | Everything in one go: `install`, `conf`, `alias`, `plugins`, `boot` (each also runs alone) |

## Surviving reboots

tmux itself dies on shutdown, so this repo saves and rebuilds the environment instead:

- **tmux-continuum** saves every 5 min; **tmux-resurrect** restores sessions, named windows, panes, directories and pane contents.
- `tm boot` installs a systemd user service: tmux starts at login (restoring the last save) and saves again on a clean shutdown.
- `claude` panes are relaunched as `claude --continue` (see `@resurrect-processes` in `tmux.conf`). This is untested: if it doesn't match, adjust that line.
- **Not restored:** running processes (`npm run dev`, `docker compose logs`, ...). You get the pane in the right directory; restart the command, or add it to `@resurrect-processes`.
- Manual save/restore: `Ctrl+b` `Ctrl+s` / `Ctrl+b` `Ctrl+r`.
- Name windows with `Ctrl+b` `,` — the names survive the restore.

## Using tmux

- **Leave without killing:** `Ctrl+b`, release, `d`. Never `exit` or `Ctrl+d`: that closes the shell and ends the session.
- **Prefix is two steps:** press `Ctrl+b`, release everything, then press the next key. Nested tmux (e.g. SSH inside tmux): press `Ctrl+b` twice.
- tmux is per user and per machine.

Common keys (after the prefix):

| Key | Action |
|---|---|
| `d` | Detach |
| `c` / `,` | New / rename window |
| `n` / `p` / `0-9` | Next / previous / go to window |
| `%` / `"` | Split vertical / horizontal |
| arrows | Move between panes |
| `z` | Zoom pane (toggle) |
| `x` | Close pane |
| `[` | Scroll mode (`q` to exit) |
| `?` | List all keys |

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Ctrl+b` does nothing | Not inside tmux (no green status bar), or `d` pressed together with it |
| `no server running` | No session: other user/machine, or it died after `exit` |
| `sessions should be nested with care` | Already inside tmux; detach first |
| Scroll doesn't work | Run `tm conf` (enables mouse) or use `Ctrl+b [` |

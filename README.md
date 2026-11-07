# tmux-guia

My tmux config plus a Makefile of session shortcuts (`tm`). Keeps terminals alive across SSH drops and lets you attach to the same session from any machine.

## Setup (Ubuntu)

```sh
sudo apt install -y git make
git clone git@github.com:pablomelo-inf/tmux-guia.git
cd tmux-guia
make setup     # installs tmux if missing, links tmux.conf, adds alias, installs plugins, enables boot service
```

Clone anywhere: the alias points to wherever you cloned. Without an SSH key on GitHub, clone via `https://github.com/pablomelo-inf/tmux-guia.git` instead.

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

## Copy & paste

- **Copy:** select with the mouse; on release the text is copied. In copy mode (`Ctrl+b [`) use `Space` to start selecting and `Enter` to copy.
- **Scroll:** mouse wheel or `PageUp` (no need for `Ctrl+b [`); scrolling back to the bottom leaves copy mode.
- **Paste:** middle click, or `Ctrl+b ]`.
- Mouse copy goes to the tmux buffer, so middle click / `Ctrl+b ]` paste it inside tmux. It reaches the system clipboard only if `wl-copy`/`xclip`/`xsel` is installed. Without one of them (e.g. GNOME Terminal), to copy to other apps, use `Shift`+drag and `Ctrl+Shift+C` (below).
- `Shift`+drag skips tmux and uses the terminal's own selection; then `Ctrl+Shift+C` copies and `Ctrl+Shift+V` pastes (those two keys belong to the terminal, tmux never sees them).

## Terminal tab title

`set-titles` in `tmux.conf` sends the tmux session name to the terminal, so each tab/window is titled with its session (e.g. `projetolivro`) instead of `user@host: ~`. To also show the window, change `set-titles-string` to `'#S:#W'`. If the title doesn't change in GNOME Terminal, set the profile's *Title and Command* → initial title option to *Replace initial title*, and open a new tab.

## Surviving reboots

tmux itself dies on shutdown, so this repo saves and rebuilds the environment instead:

- **tmux-continuum** saves every 5 min; **tmux-resurrect** restores sessions, named windows, panes, directories and pane contents.
- `tm boot` installs a systemd user service: tmux starts at login (restoring the last save) and saves again on a clean shutdown. The unit is a *copy* in `~/.config/systemd/user/`, so it survives moving the repo; re-run `tm boot` after editing `tmux.service`.
- **SSH drops / last logout:** without lingering, systemd stops your services when your last session ends, which also stops tmux. Run `loginctl enable-linger` once to avoid that (`tm boot` reminds you).
- `@continuum-boot 'on'` in `tmux.conf` is required: otherwise continuum runs `systemctl --user disable tmux.service` on every start and the service hangs until its 90 s timeout.
- `claude` panes are relaunched as `claude --continue` (see `@resurrect-processes` in `tmux.conf`). This is untested: if it doesn't match, adjust that line.
- **Not restored:** running processes (`npm run dev`, `docker compose logs`, ...). You get the pane in the right directory; restart the command, or add it to `@resurrect-processes`.
- **Privacy:** `@resurrect-capture-pane-contents` saves pane text (anything shown on screen, secrets included) in plain text under `~/.local/share/tmux/resurrect`. `tm plugins` makes that folder owner-only (`700`). Remove that line from `tmux.conf` if you don't want it.
- **Plugins are pinned** to audited commits in the `Makefile` (they run code on every tmux start). To update: review the diff upstream, then change the `*_SHA` lines.
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
| `tm boot` then `systemctl --user start tmux` hangs 90 s | `@continuum-boot` is not `'on'` in `tmux.conf` (see above), or the unit is stale: re-run `tm boot` |
| `tm kill clean` says the name is also a command | Names equal to a command are refused so they never run it: use `tm kill S=clean` |
| `Ctrl+b` does nothing | Not inside tmux (no green status bar), or `d` pressed together with it |
| `no server running` | No session: other user/machine, or it died after `exit` |
| `sessions should be nested with care` | Already inside tmux; detach first |
| Scroll doesn't work | Run `tm conf` (enables mouse) or use `Ctrl+b [` |

## Development

```sh
tests/test.sh                 # offline tests, in a throwaway HOME and tmux socket
RUN_NETWORK=1 tests/test.sh   # also installs the plugins and checks the pinned commits
```

CI (`.github/workflows/ci.yml`) runs `shellcheck` and the full test suite on every push and PR. Plugins are pinned to audited commits (`*_SHA` in the `Makefile`); to update one, review the upstream diff first. Dependabot keeps the GitHub Actions up to date.

The `tm` arguments never reach the shell as code, and a session named like a command (`clean`, `kill`...) is refused as a positional argument; use `S=`/`N=` for those.

## License

MIT, see [LICENSE](LICENSE).

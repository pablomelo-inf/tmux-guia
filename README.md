# tmux-guia

My tmux config plus `tm`, a small command for sessions. Keeps terminals alive across SSH drops and reboots, and lets you attach to the same session from any machine. Needs tmux 3.2+.

## Setup (Ubuntu)

```sh
sudo apt install -y git make
git clone git@github.com:pablomelo-inf/tmux-guia.git
cd tmux-guia
make setup     # tmux if missing, config link, tm in ~/.local/bin, plugins, boot service
```

Clone anywhere: `tm` is a link to wherever you cloned. Without an SSH key on GitHub, clone via `https://github.com/pablomelo-inf/tmux-guia.git`. Open a new terminal afterwards. Check everything with `tm doctor`.

**Upgrading from the make-based `tm` (1.x):** run `make setup` once; it replaces the old alias in `~/.bashrc` (backup kept).

## Updating

`tm update` pulls the repo (fast-forward only), re-links, re-pins plugins and the boot unit if they changed, and reloads the config in running sessions.

## Commands

| Command | Does |
|---|---|
| `tm` | Pick a session with fzf (or show the help) |
| `tm ls` | List sessions (in use / free) and their folders |
| `tm attach NAME [DIR]` | Attach, creating the session (in DIR) if missing; inside tmux it switches |
| `tm create NAME [DIR]` | Create detached |
| `tm open [--all] [NAME...]` | One terminal tab per session (default: free ones); `TM_TERMINAL=...` forces a terminal |
| `tm detach NAME` | Detach clients, keep session running |
| `tm rename OLD NEW` | Rename |
| `tm kill NAME` | Kill session |
| `tm clean` / `tm kill-all` | Kill free sessions / everything (asks first) |
| `tm save` / `tm restore` | Save now / restore the last save |
| `tm doctor` | Check the installation |
| `tm update` | Pull and apply changes |
| `tm setup` | `install`, `conf`, `link`, `plugins`, `boot` in one go (each also runs alone) |
| `tm uninstall` | Undo setup (keeps plugins and saved sessions) |

Names are plain data: a session may be called `clean`, `a b` or `-x`. Targets are exact (`tm kill pro` never hits `projeto`). `tm open` supports GNOME Terminal, Konsole, Xfce, kitty and WezTerm; any other terminal gets one window per session. Completion for bash, zsh and fish is installed by `tm link` (zsh: add `~/.local/share/zsh/site-functions` to `fpath`).

Machine-specific tmux settings go in `~/.tmux.local.conf` (loaded at the end, not in the repo). `Ctrl+b r` reloads the config.

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
- `tm boot` installs a systemd user service: tmux starts at login (restoring the last save) and saves again on a clean shutdown. The unit is a *copy* in `~/.config/systemd/user/` with this machine's tmux path filled in; `tm update` refreshes it when it changes.
- **Locale:** without a UTF-8 locale tmux prints tabs as `_` and tmux-resurrect writes empty saves silently. The unit and `tm save`/`tm restore` force `C.UTF-8` for that, and the tests cover it.
- **SSH drops / last logout:** without lingering, systemd stops your services when your last session ends, which also stops tmux. Run `loginctl enable-linger` once to avoid that (`tm boot` reminds you).
- `@continuum-boot 'on'` in `tmux.conf` is required: otherwise continuum runs `systemctl --user disable tmux.service` on every start and the service hangs until its 90 s timeout.
- `claude` panes come back with **their own conversation**: on each save, `tm _save-hook` (`@resurrect-hook-post-save-layout`) writes `claude --resume ID`, reading the ID from the file claude keeps per process (`~/.claude/sessions/PID.json`). Plain `--continue` reopened the newest conversation of the folder, so sessions sharing a folder (often `~`) got each other's. Without that file it falls back to `claude --continue`. Covered by the tests.
- **Folders on other disks:** if a pane's folder is missing at boot (a disk not mounted yet), tmux opens it in `~`; the hook keeps the old folder in the next saves, so it comes back once the disk is there. For the session to open in the right folder at boot, mount that disk in `/etc/fstab` (with `nofail`) instead of from the desktop.
- **One folder per session:** `tm ls` shows each session's folder, and `tm attach NAME` without a DIR warns when the session would start in `~`.
- **Not restored:** running processes (`npm run dev`, `docker compose logs`, ...). You get the pane in the right directory; restart the command, or add it to `@resurrect-processes`.
- **Privacy:** `@resurrect-capture-pane-contents` saves pane text (anything shown on screen, secrets included) in plain text under `~/.local/share/tmux/resurrect`. `tm plugins` makes that folder owner-only (`700`). Remove that line from `tmux.conf` if you don't want it.
- **Plugins are pinned** to audited commits in `bin/tm` (they run code on every tmux start). To update: review the diff upstream, then change the `*_SHA` lines in `bin/tm`.
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
| `tm: command not found` after `tm setup` | `~/.local/bin` is not in PATH yet: open a new terminal or log in again |
| `make attach work` says "now a command of bin/tm" | The old alias is still active: run `tm link` once |
| `Ctrl+b` does nothing | Not inside tmux (no green status bar), or `d` pressed together with it |
| `no server running` | No session: other user/machine, or it died after `exit` |
| `sessions should be nested with care` | Plain `tmux attach` inside tmux; use `tm attach NAME`, which switches instead |
| Scroll doesn't work | Run `tm conf` (enables mouse) or use `PageUp` |

## Development

```sh
make test         # offline tests, in a throwaway HOME and tmux socket
make docker-test  # same suite in clean Ubuntu 22.04 (tmux 3.2a) and 24.04 (3.4) containers
make lint         # shellcheck, markdownlint, systemd unit
make audit        # security checks (needs Docker)
RUN_NETWORK=1 make test   # also installs plugins, checks pins, save/restore and claude --resume
```

The suite is also the regression suite: every fixed bug keeps a test that fails on the old code. Containers mount the repo read-only and run as non-root.

### Security audit

| Tool | Checks |
|---|---|
| gitleaks | Secrets in the whole git history |
| zizmor | GitHub Actions and Dependabot config |
| hadolint | `tests/Dockerfile` |
| trivy | Secrets and misconfigurations in the repo; fixable HIGH/CRITICAL CVEs in both test images |

Scanners, base images, actions and plugins are pinned by digest/SHA; Dependabot proposes updates after a 7-day cooldown. Accepted findings are listed with a reason (`.trivyignore`, `# hadolint ignore=`).

CI (`.github/workflows/ci.yml`) runs lint, the audit and the tests on both Ubuntu versions on every push and PR, and the audit weekly so new CVEs are caught without a push.

To update a plugin: review the upstream diff, change its `*_SHA` in `bin/tm`, run `tm plugins`.

## License

MIT, see [LICENSE](LICENSE).

# dotfiles

Personal machine bootstrap and config management. One command sets up a new
machine: developer tools, GitHub authentication (gh CLI + SSH), opencode,
tmux/nvim configs — all idempotent, safe to re-run any time.

## Managed files

| Repo file                          | Deployed to                            |
|------------------------------------|----------------------------------------|
| `bashrc`                           | `~/.bashrc` (symlink)                  |
| `bash_profile`                     | `~/.bash_profile` (symlink)            |
| `tmux.conf`                        | `~/.tmux.conf` (symlink)               |
| `config/nvim/`                     | `~/.config/nvim` (symlink)             |
| `config/opencode/opencode.jsonc`   | `~/.config/opencode/opencode.jsonc` (generated, see below) |
| `config/claude/settings.json`      | `~/.claude/settings.json` (generated, see below) |

Everything under `config/<app>/` mirrors the XDG layout: it deploys to
`~/.config/<app>/`. Claude Code is the exception — it reads `~/.claude/`, not
XDG — so `config/claude/` deploys there instead.

## Prerequisites

- **git** — everything else the installer can set up itself (sudo-less
  machines degrade gracefully, see FAQ).
- macOS only: Xcode CLT (`xcode-select --install`) and
  [Homebrew](https://brew.sh).

## Quickstart

```bash
git clone git@github.com:KonstantinPakulev/dotfiles ~/dotfiles
cd ~/dotfiles
./install.sh              # interactive
./install.sh --yes        # non-interactive (containers, CI)
./install.sh --proxy=http://localhost:8888   # route downloads through a proxy
```

What it does, in order:

1. **Tools** — installs gh, tmux (≥ 3.3 checked; pinned to 3.5a on macOS,
   see FAQ), nvim, jq, yazi (+ `ya`),
   lazydocker (skipped when Docker is absent), JetBrainsMono Nerd Font,
   opencode via brew (macOS) or apt/official tarballs (Linux). See
   `install/tools.sh`.
2. **GitHub auth** — if unauthenticated, prints a single-shot
   `gh auth login` command to run, then re-run the installer.
3. **SSH** — generates an ed25519 key if missing, pins GitHub's published
   host keys (no trust-on-first-use), adds the `github.com` block to
   `~/.ssh/config`, registers the key via gh on first use.
4. **Private layer** — clones/pulls
   [`dotfiles-private`](https://github.com/KonstantinPakulev/dotfiles-private)
   into `~/dotfiles-private`; skipped with a warning when unavailable.
5. **Links** — symlinks the table above into `$HOME`, clones tpm, and wires
   the private ssh fragments. Existing files are
   never silently overwritten: you get `[b]ackup/[d]iff/[k]eep/[A]ll/[q]uit`
   per file. Backups land next to the original as `<name>.backup.<timestamp>`.
6. **opencode config** — see below.
7. **Claude Code config** — same mechanism, see below.

## The private layer

`config/opencode/opencode.jsonc` in this repo holds only generic settings
(permissions, compaction, LSP) because this repo is public. Provider configs
(model backends) and machine-specific settings (allowed external directories)
live in the **private companion repo**
[`KonstantinPakulev/dotfiles-private`](https://github.com/KonstantinPakulev/dotfiles-private):

```
dotfiles-private/
├── opencode/
│   └── opencode.jsonc    # private counterpart: providers, permissions
├── claude/
│   └── settings.json     # private counterpart: model, theme, plugins
└── ssh/
    └── config.d/
        └── fleet.conf    # lab hosts: IPs, usernames, jump hosts
```

When the installer finds that repo (it clones/pulls it to `~/dotfiles-private`),
the two configs are deep-merged with jq into generated real files at
`~/.config/opencode/opencode.jsonc` and `~/.claude/settings.json` — marked
"generated", do not edit. Without the private repo, the public configs are
symlinked as-is.

The Claude merge differs from the opencode one in two ways, both forced by
Claude Code:

- `settings.json` is **strict JSON**, so the "generated" marker is a top-level
  `"//"` key rather than a `//` comment line. A malformed settings file silently
  disables every setting in it, so the script validates before installing.
- its interesting keys are **arrays** (`permissions.allow`/`deny`/`ask`). jq's
  `*` replaces arrays rather than unioning them, so the filter concatenates them
  explicitly — otherwise the private layer's short list would wipe the public one.

**The proxy is not stored in either repo.** `http://127.0.0.1:8888` is only
correct on the machine running that proxy, and the private repo is shared across
machines too. Instead `install/claude-config.sh` injects `env.HTTP_PROXY` (and
the three case/scheme variants) from `--proxy=<url>` at generation time — the
same flag every other stage takes. The generated file lives outside any repo, so
it can hold a value the repos must not:

```bash
./install/claude-config.sh --proxy=http://127.0.0.1:8888   # this machine
./install/claude-config.sh                                 # no proxy, no env block
```

One caveat where a dev container bind-mounts `~/.claude` (as the Summertime
`develop` service does): the host and the container then share **one**
`settings.json`, so they also share one proxy value — it is not per-environment.
That is fine only while the same URL is valid on both sides. In Summertime it is:
the vpn service publishes `8888` to the host, and `develop` shares the vpn network
namespace, so `127.0.0.1:8888` reaches the same tinyproxy either way. If the two
ever need different addresses, this scheme cannot express it and the proxy has to
move to something evaluated per-environment (a shell export, say).

Note also that these `env` vars reach Claude Code's process tree only — not
code-server, not your interactive shells, not anything else in the container or
on the host. Requests from Claude Code (including a host-run one, since it reads
the same bind-mounted file) go through the proxy; everything else does not.

Note that Claude Code writes to `~/.claude/settings.json` itself (`/config`
toggles such as theme and model, and user-scope "don't ask again"). Those writes
are overwritten the next time the script runs — promote anything worth keeping
into `config/claude/settings.json` or the private layer first.

SSH fragments work differently — no merging, pure registration: the
installer symlinks `ssh/config.d/*.conf` into `~/.ssh/config.d/` and
guarantees a single `Include ~/.ssh/config.d/*` line at the top of
`~/.ssh/config`. Your hand-tuned main config is never rewritten; network
topology and usernames stay out of the public repo.

The generated output lives outside any repository, so merged content can
never be accidentally committed.

## Updating

```bash
git -C ~/dotfiles pull
./install.sh                    # idempotent; re-syncs the private layer itself
# or granular:
./install/opencode-config.sh    # regenerate merged opencode config
./install/claude-config.sh      # regenerate merged Claude Code config
./install/link.sh               # pick up newly added mappings
./install/tools.sh              # only when you want tool upgrades
```

## Machine-specific settings

Shared configs ship a universal interactive baseline (history, completion,
colored prompt, core aliases); per-machine tweaks go into gitignored locals:

- `~/.bashrc.local` — sourced at the end of `~/.bashrc`
- `~/.bash_profile.local` — sourced at the end of `~/.bash_profile`
  (nvm, pyenv, machine PATH entries belong here)

## FAQ

**Why `--insecure-storage` for gh?**
macOS Keychain ACLs allow token reads from Terminal.app but silently deny
them from iTerm2/tmux/opencode-spawned shells (exit 36, empty token).
`--insecure-storage` keeps the token in `~/.config/gh/hosts.yml` (0600)
instead. Note: never run `gh auth refresh` afterwards — it re-enrolls the
token into Keychain; re-login single-shot instead.

**Why does the installer pass `--no-modify-path` to opencode's installer?**
PATH is exported by our managed `~/.bashrc`. The official installer would
otherwise append its own export line into `~/.bashrc` — which is a symlink
into this repo.

**Icons render wrong (`_` or tofu boxes)?**
Two distinct failures with different fixes. An `_` on *everything*
inside tmux means tmux classified your client as non-UTF-8
(`client_utf8`) because the login shell has no locale — stock macOS
sshd sessions start without one. The managed `bashrc` exports
`en_US.UTF-8` when unset: start a fresh login shell and restart tmux.
Tofu boxes `□` on icon glyphs (nvim/yazi/status bar) are a font matter:
icon glyphs live in the Unicode Private Use Area, which only Nerd Fonts
implement — when no Nerd Font exists on the rendering device, fallback
chains find nothing to substitute and draw `.notdef` (ordinary text is
unaffected and always falls back fine). The installer provisions
JetBrainsMono Nerd Font on this machine so local sessions render; for
remote work, install a Nerd Font on whichever device runs your terminal
app — on Linux/macOS having it installed usually suffices even without
selecting it in the app's settings.

**tmux complains about `allow-passthrough`?**
That option needs tmux ≥ 3.3. Ubuntu 22.04 ships 3.2a: either enable
backports/a PPA or build from source (needs `libevent-dev ncurses-dev
bison pkg-config`). macOS Homebrew is always current.

**Why is tmux pinned to 3.5a on macOS?**
Newer releases emit pane diffs in a way that renders poorly over SSH to
Termius on iPad: random jitter whenever a TUI repaints and gray flash
rectangles at nvim scroll boundaries (verified against 3.7c; 3.5a is
clean with identical config and client). The installer therefore builds
3.5a from the official tarball into `~/.local/opt/tmux-3.5a` and shadows
brew's binary via `~/.local/bin/tmux`, which the managed bashrc places
first on PATH. To experiment with a newer version anyway, remove that
shadow symlink.

**Machines without sudo?**
Every apt touchpoint probes privilege first: running as root, or sudo usable
without a password, or an interactive TTY (where sudo may prompt). With none
of those, the installer degrades instead of aborting: **gh** and **jq** fall
back to official release binaries in `~/.local/bin` (nvim/yazi/lazydocker
already install that way); **tmux**, **yazi** (unzip missing) and fonts
(fontconfig missing) are skipped with a warning — hints for building tmux
from source are above. Set `DOTFILES_NO_SUDO=1` to force the user-local path
even where sudo exists (rehearsals, restricted CI). Everything after the
tools stage (GitHub auth, SSH keys, linking, private layer) never needs root.

**Uninstall?**
There is no uninstall script — removal is intentionally manual so nothing
deletes files without you looking at them:

```bash
rm ~/.bashrc ~/.bash_profile ~/.tmux.conf ~/.config/nvim \
   ~/.config/opencode/opencode.jsonc     # all symlinks / generated file
ls ~ ~/.config | grep backup             # review .backup.<timestamp> files,
                                         # restore any you want back
rm -rf ~/dotfiles-private               # private layer clone
gh auth logout --hostname github.com     # drop the gh token
```

## Security notes

- GitHub host keys are pinned from `api.github.com/meta` before first SSH
  contact; hardcoded fallback constants should match
  [GitHub's published fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).
- A defensive [.gitignore](.gitignore) blocks common secret filenames
  (keys, tokens, auth files) from ever being committed here by accident.

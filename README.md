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

Everything under `config/<app>/` mirrors the XDG layout: it deploys to
`~/.config/<app>/`.

## Prerequisites

- **git** — everything else the installer can set up itself.
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

1. **Tools** — installs gh, tmux (≥ 3.3 checked), nvim, jq, yazi (+ `ya`),
   lazydocker (skipped when Docker is absent), JetBrainsMono Nerd Font,
   opencode via brew (macOS) or apt/official tarballs (Linux). See
   `install/tools.sh`.
2. **GitHub auth** — if unauthenticated, prints a single-shot
   `gh auth login` command to run, then re-run the installer.
3. **SSH** — generates an ed25519 key if missing, pins GitHub's published
   host keys (no trust-on-first-use), adds the `github.com` block to
   `~/.ssh/config`, registers the key via gh on first use.
4. **Links** — symlinks the table above into `$HOME`. Existing files are
   never silently overwritten: you get `[b]ackup/[d]iff/[k]eep/[A]ll/[q]uit`
   per file. Backups land next to the original as `<name>.backup.<timestamp>`.
5. **opencode config** — see below.

## The private layer

`config/opencode/opencode.jsonc` in this repo holds only generic settings
(permissions, compaction, LSP) because this repo is public. Provider configs
(model backends) live in the **private companion repo**
[`KonstantinPakulev/dotfiles-private`](https://github.com/KonstantinPakulev/dotfiles-private):

```
dotfiles-private/
└── opencode/
    └── provider.jsonc    # {"provider": { "<name>": {...} }}
```

When the installer finds that repo (it clones/pulls it to `~/.dotfiles-private`),
the two configs are deep-merged with jq into a generated real file at
`~/.config/opencode/opencode.jsonc` — marked "generated", do not edit.
Without the private repo, the public config is symlinked as-is.

The generated output lives outside any repository, so merged content can
never be accidentally committed.

## Updating

```bash
git -C ~/dotfiles pull && git -C ~/.dotfiles-private pull   # if present
./install/opencode-config.sh    # regenerate merged config
./install/link.sh               # pick up newly added mappings
./install/tools.sh              # only when you want tool upgrades
```

## Machine-specific settings

Shared configs stay pristine; per-machine tweaks go into gitignored locals:

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

**Uninstall?**
There is no uninstall script — removal is intentionally manual so nothing
deletes files without you looking at them:

```bash
rm ~/.bashrc ~/.bash_profile ~/.tmux.conf ~/.config/nvim \
   ~/.config/opencode/opencode.jsonc     # all symlinks / generated file
ls ~ ~/.config | grep backup             # review .backup.<timestamp> files,
                                         # restore any you want back
rm -rf ~/.dotfiles-private               # private layer clone
gh auth logout --hostname github.com     # drop the gh token
```

## Security notes

- GitHub host keys are pinned from `api.github.com/meta` before first SSH
  contact; hardcoded fallback constants should match
  [GitHub's published fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).
- A defensive [.gitignore](.gitignore) blocks common secret filenames
  (keys, tokens, auth files) from ever being committed here by accident.

#!/usr/bin/env bash
# install/link.sh — link configs into $HOME (interactive conflict handling),
# set up tpm and wire private-layer ssh fragments. Safe to re-run.
#   ./install/link.sh [--proxy=<url>] [--dry-run] [--yes]

set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

REPO_SRC="$DOTFILES_ROOT"
SKIPPED=0
LINKED=0

MAPPINGS=(
    "bashrc|$HOME/.bashrc"
    "bash_profile|$HOME/.bash_profile"
    "tmux.conf|$HOME/.tmux.conf"
    "config/nvim|$HOME/.config/nvim"
)

link_mapping() {
    local src="$1" dst="$2"

    [ -e "$REPO_SRC/$src" ] || die "repo file missing: $REPO_SRC/$src"
    mkdir -p "$(dirname "$dst")"

    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
        log "linking $dst"
        run ln -sn "$REPO_SRC/$src" "$dst"
        LINKED=$((LINKED + 1))
        return 0
    fi

    # Dangling symlink -> repair silently
    if [ -L "$dst" ] && [ ! -e "$dst" ]; then
        warn "repairing dangling symlink $dst"
        run rm "$dst"
        run ln -sn "$REPO_SRC/$src" "$dst"
        LINKED=$((LINKED + 1))
        return 0
    fi

    # Already ours -> done
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$REPO_SRC/$src" ]; then
        log "already linked: $dst"
        return 0
    fi

    # Foreign symlink or real file/dir -> conflict menu (lib.sh)
    handle_conflict "$src" "$dst"
}

setup_tpm() {
    local tpm_dir="$HOME/.tmux/plugins/tpm"
    if [ -d "$tpm_dir" ]; then
        log "tpm already present"
    else
        log "Cloning tpm..."
        run git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm_dir"
    fi
    if [ -x "$tpm_dir/bin/install_plugins" ]; then
        log "Installing tmux plugins (headless)..."
        if $DRY_RUN; then
            echo "[dry-run] $tpm_dir/bin/install_plugins"
        elif ! "$tpm_dir/bin/install_plugins" >/dev/null 2>&1; then
            warn "tpm plugin install failed (offline?) — press prefix+I inside tmux later"
        fi
    fi
}

setup_ssh() {
    local frag_src="$HOME/.dotfiles-private/ssh/config.d"
    local frag_dst="$HOME/.ssh/config.d"
    mkdir -p "$frag_dst"

    # Fragments live in the private layer (network topology, usernames);
    # this repo only guarantees the mechanism.
    if [ -d "$frag_src" ] && [ -n "$(ls -A "$frag_src" 2>/dev/null)" ]; then
        local f
        for f in "$frag_src"/*.conf; do
            run ln -snf "$f" "$frag_dst/$(basename "$f")"
        done
    else
        log "no private ssh fragments found (optional)"
    fi

    # ~/.ssh/config is user-owned territory: never rewrite it beyond
    # guaranteeing a single Include line that picks up the fragments.
    local cfg="$HOME/.ssh/config"
    if [ ! -e "$cfg" ]; then
        log "creating $cfg with Include line"
        run touch "$cfg"
    fi
    if ! grep -qs '^Include.*/config\.d' "$cfg"; then
        log "prepending Include line to $cfg"
        if $DRY_RUN; then
            echo "[dry-run] prepend 'Include ~/.ssh/config.d/*' to $cfg"
        else
            local tmp
            tmp="$(mktemp)"
            { printf 'Include ~/.ssh/config.d/*\n\n'; cat "$cfg"; } > "$tmp"
            mv "$tmp" "$cfg"
        fi
    fi
}

link_main() {
    log "Linking configs..."
    for mapping in "${MAPPINGS[@]}"; do
        src="${mapping%%|*}"
        dst="${mapping#*|}"
        link_mapping "$src" "$dst" || SKIPPED=$((SKIPPED + 1))
    done
    setup_tpm
    setup_ssh
    log "Linking done: linked=$LINKED skipped=$SKIPPED"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_common_args "$@"
    link_main
fi

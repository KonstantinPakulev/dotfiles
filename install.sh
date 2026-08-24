#!/usr/bin/env bash
# dotfiles installer — orchestrator.
# Bootstraps tools, GitHub auth, SSH keys and links configs. Idempotent: safe to re-run.
#
# Usage: ./install.sh [--proxy=<url>] [--dry-run] [--yes]
# Stages live in install/*.sh and are individually re-runnable, e.g.:
#   ./install/tools.sh             # (re)install binaries only
#   ./install/opencode-config.sh   # regenerate merged opencode config
#   ./install/link.sh              # (re)link configs after pulling

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install/lib.sh"
parse_common_args "$@"
detect_platform

command -v git >/dev/null 2>&1 \
    || die "git is required but not installed. See README.md prerequisites."

log "dotfiles installer — $OS ($ARCH), from $DOTFILES_ROOT"

# ---------------------------------------------------------------------------
# Stage 1: tools
# ---------------------------------------------------------------------------
# shellcheck source=install/tools.sh
source "$INSTALL_DIR/tools.sh"
tools_main

# ---------------------------------------------------------------------------
# Stage 2: GitHub authentication
# ---------------------------------------------------------------------------
if ! gh auth status >/dev/null 2>&1; then
    cat <<EOF

$(printf '\033[1;33mAction required:\033[0m this machine is not authenticated with GitHub.')
Run the following single-shot login, then re-run ./install.sh:

    gh auth logout --hostname github.com 2>/dev/null; \\
      BROWSER=true gh auth login --hostname github.com --git-protocol ssh --web \\
         --insecure-storage --scopes "repo,gist,read:org,admin:public_key"

(--insecure-storage stores the token in ~/.config/gh/hosts.yml with 0600 perms
 instead of the macOS Keychain, whose ACLs break across terminal apps and tmux.
 BROWSER=true suppresses the useless local-browser launch on headless hosts:
 open https://github.com/login/device on ANY device and enter the one-time
 code; this session finishes polling on its own.)
EOF
    exit 1
fi
log "GitHub auth OK: $(gh api user -q .login)"

# ---------------------------------------------------------------------------
# Stage 3: SSH key lifecycle
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$KEY" ]; then
    log "Generating ed25519 key pair..."
    run ssh-keygen -t ed25519 -N "" -f "$KEY" -C "$USER@$(hostname -s)"
else
    log "SSH key already present: $KEY"
fi

# Pin GitHub's published host keys BEFORE first contact (no trust-on-first-use).
KH="$HOME/.ssh/known_hosts"
touch "$KH"
pin_host_keys() {
    local fetched
    fetched="$(curl "${CURL_ARGS[@]+${CURL_ARGS[@]}}" -fsSL https://api.github.com/meta 2>/dev/null \
        | sed -n 's/.*"\(ssh-[a-z0-9]*\|ecdsa-sha2-[a-z0-9-]*\)": *"\([A-Za-z0-9+/=]\{50,\}\)".*/\1 \2/p') || true"
    if [ -z "$fetched" ]; then
        # Fallback constants — verify against docs.github.com SSH fingerprints
        fetched="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
    fi
    while read -r alg key; do
        local line="github.com $alg $key"
        grep -qxF "$line" "$KH" || echo "$line" >> "$KH"
    done <<EOF
$fetched
EOF
}
log "Pinning github.com host keys..."
if $DRY_RUN; then echo "[dry-run] would update $KH"; else pin_host_keys; fi

SC="$HOME/.ssh/config"
touch "$SC"
chmod 600 "$SC"
if ! grep -qE '^Host github\.com$' "$SC"; then
    log "Adding github.com block to ~/.ssh/config..."
    run tee -a "$SC" > /dev/null <<'EOF'

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
EOF
fi

ssh_ok() {
    { ssh -T -o BatchMode=yes -o ConnectTimeout=10 git@github.com 2>&1 || true; } | grep -q '^Hi '
}

if ssh_ok; then
    log "SSH authentication with GitHub OK"
else
    log "Registering public key with GitHub..."
    if $DRY_RUN; then
        echo "[dry-run] gh ssh-key add '$KEY.pub' --title '$(hostname -s)-ed25519'"
    else
        gh ssh-key add "$KEY.pub" --title "$(hostname -s)-ed25519"
        ssh_ok || die "SSH auth still failing after key registration"
    fi
    log "SSH authentication with GitHub OK"
fi

# ---------------------------------------------------------------------------
# Stage 4: link configs + tpm
# ---------------------------------------------------------------------------
# shellcheck source=install/link.sh
source "$INSTALL_DIR/link.sh"
link_main

# ---------------------------------------------------------------------------
# Stage 5: deploy opencode config (merge private layer when present)
# ---------------------------------------------------------------------------
# shellcheck source=install/opencode-config.sh
source "$INSTALL_DIR/opencode-config.sh"
opencode_config_main

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
cat <<EOF

$(printf '\033[1;32mDone.\033[0m')
Checklist:
  - opencode: $(command -v opencode || echo "$HOME/.opencode/bin added after new shell")
  - tmux:     $(command -v tmux || echo 'MISSING')
  - nvim:     $(command -v nvim || echo 'MISSING')
  - gh:       $(command -v gh || echo 'MISSING')
Start a new shell (or: source ~/.bashrc) to pick up PATH changes.
EOF

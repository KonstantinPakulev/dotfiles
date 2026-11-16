#!/usr/bin/env bash
# install/yazi-packages.sh — install packages declared in config/yazi/package.toml.

set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

sync_sshfs_hosts() {
    local frag_src="$HOME/dotfiles-private/ssh/config.d"
    local output="$HOME/.local/share/yazi/sshfs.list"
    local fragments=("$frag_src"/*.conf)
    [ -e "${fragments[0]}" ] || { log "no private SSH fragments found for SSHFS hosts (optional)"; return 0; }

    if $DRY_RUN; then
        echo "[dry-run] would generate $output from private SSH fragments"
        return 0
    fi

    local tmp
    tmp="$(mktemp)"
    awk '$1 == "Host" {
        for (i = 2; i <= NF; i++) {
            if ($i !~ /[*?!]/) print $i
        }
    }' "${fragments[@]}" | sort -u > "$tmp"
    mkdir -p "$(dirname "$output")"
    if ! cmp -s "$tmp" "$output"; then
        mv "$tmp" "$output"
        chmod 600 "$output"
        log "SSHFS host list updated: $output"
    else
        rm "$tmp"
        log "SSHFS host list already up to date"
    fi
}

yazi_packages_main() {
    sync_sshfs_hosts
    if ! command -v ya >/dev/null 2>&1; then
        warn "ya not found — skipping Yazi packages"
        return 0
    fi
    if [ ! -f "$HOME/.config/yazi/package.toml" ]; then
        log "no Yazi package manifest found (optional)"
        return 0
    fi
    log "Installing Yazi packages..."
    run ya pkg install
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_common_args "$@"
    yazi_packages_main
fi

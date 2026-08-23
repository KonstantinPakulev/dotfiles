#!/usr/bin/env bash
# Shared helpers for dotfiles installer modules. Source this, never execute it.

# Include guard: modules are sourced by the orchestrator which already parsed
# flags into globals — re-initializing here would wipe them.
if [ -n "${_DOTFILES_LIB_LOADED:-}" ]; then
    return 0
fi
_DOTFILES_LIB_LOADED=1

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # used by sourced modules
DOTFILES_ROOT="$(dirname "$INSTALL_DIR")"

DRY_RUN=false
YES=false
PROXY=""
# shellcheck disable=SC2034  # consumed by modules after source
CURL_ARGS=()
OS=""
ARCH=""
PKG=""
# shellcheck disable=SC2034  # consumed by modules after source
SUDO=""

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Parse the flags every module understands. Call with the script's own "$@".
parse_common_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --proxy=*) PROXY="${1#*=}" ;;
            --dry-run) DRY_RUN=true ;;
            --yes|-y)  YES=true ;;
            -h|--help)
                sed -n '2,12p' "${BASH_SOURCE[1]}" | sed 's/^# \{0,1\}//'
                exit 0
                ;;
            *) die "unknown option: $1 (supported: --proxy=<url>, --dry-run, --yes)" ;;
        esac
        shift
    done

    if [ -n "$PROXY" ]; then
        export HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
        export http_proxy="$PROXY" https_proxy="$PROXY"
        # consumed by modules after source
        # shellcheck disable=SC2034
        CURL_ARGS=(-x "$PROXY")
    fi
}

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"
    case "$ARCH" in aarch64) ARCH=arm64 ;; esac

    case "$OS" in
        Darwin) PKG=brew ;;
        Linux)  PKG=apt ;;
        *) die "unsupported OS: $OS" ;;
    esac

    SUDO=""
    # consumed by modules after source
    # shellcheck disable=SC2034
    if [ "$(id -u)" -ne 0 ]; then SUDO=sudo; fi
}

pkg_installed() {
    if [ "$PKG" = brew ]; then
        brew list --formula "$1" >/dev/null 2>&1
    else
        dpkg -s "$1" >/dev/null 2>&1
    fi
}

run() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

backup_existing() {
    local dst="$1"
    [ -e "$dst" ] || [ -L "$dst" ] || return 0
    local backup
    backup="${dst}.backup.$(date +%Y%m%d-%H%M%S)"
    run mv "$dst" "$backup"
    warn "backed up: $dst -> $backup"
}

# Interactive conflict resolution for deploying repo file $src to $dst.
# Uses globals: YES, DRY_RUN, REPO_SRC (dir containing src).
handle_conflict() {
    local src="$1" dst="$2"

    if $YES; then
        backup_existing "$dst"
        run ln -sn "$REPO_SRC/$src" "$dst"
        return 0
    fi

    if [ ! -t 0 ]; then
        die "conflict at $dst but stdin is not interactive; re-run with --yes or resolve manually"
    fi

    while true; do
        printf '\n%s already exists.\n' "$dst"
        printf '  [b] back it up and deploy repo version\n'
        printf '  [d] show diff between existing and repo version\n'
        printf '  [k] keep my file, skip\n'
        printf '  [A] backup-and-deploy for ALL remaining conflicts\n'
        printf '  [q] abort\n'
        local ans
        read -r -p "Choice [b]: " ans
        ans="${ans:-b}"
        case "$ans" in
            b) backup_existing "$dst"; run ln -sn "$REPO_SRC/$src" "$dst"; return 0 ;;
            d) diff -u "$dst" "$REPO_SRC/$src" 2>/dev/null | head -60 || true ;;
            k) warn "keeping $dst as is"; return 1 ;;
            A) YES=true; backup_existing "$dst"; run ln -sn "$REPO_SRC/$src" "$dst"; return 0 ;;
            q) die "aborted by user" ;;
            *) echo "invalid choice" ;;
        esac
    done
}

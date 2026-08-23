#!/usr/bin/env bash
# install/tools.sh — install gh, tmux, nvim, jq, yazi, lazydocker (needs docker), fonts, opencode.
# Standalone: ./install/tools.sh [--proxy=<url>] [--dry-run]

set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

install_gh() {
    command -v gh >/dev/null 2>&1 && { log "gh already installed: $(gh --version | head -1)"; return; }
    if [ "$PKG" = brew ]; then
        command -v brew >/dev/null 2>&1 \
            || die "Homebrew is missing. Install it first — see README.md."
        pkg_installed gh && return
        log "Installing gh (brew)..."
        run brew install gh
    else
        if $DRY_RUN; then
            echo "[dry-run] would install gh via official apt repo (fallback: plain apt)"
            return
        fi
        log "Installing gh..."
        if gh_install_official_apt_repo 2>/dev/null; then
            log "gh installed from official apt repo"
        else
            warn "official repo failed; falling back to distro package (may be old)"
            run $SUDO apt-get install -y gh
        fi
    fi
}

# Called inside an if-condition: errexit is suspended there, so any failing
# step simply makes the function return non-zero for the caller's fallback.
gh_install_official_apt_repo() {
    curl "${CURL_ARGS[@]+${CURL_ARGS[@]}}" -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    $SUDO apt-get update -qq
    $SUDO apt-get install -y gh
}

# Build the pinned tmux release into ~/.local/opt and shadow whatever
# brew/system provides. macOS only.
build_tmux_pinned_macos() {
    log "Building tmux 3.5a from official tarball..."
    command -v pkg-config >/dev/null 2>&1 \
        || die "pkg-config missing (brew install pkgconf)"
    pkg-config libevent >/dev/null 2>&1 \
        || die "libevent missing (brew install libevent)"
    local dir tmp
    dir="$HOME/.local/opt/tmux-3.5a"
    tmp="$(mktemp -d)"
    curl "${CURL_ARGS[@]+"${CURL_ARGS[@]}"}" -fsSL --output "$tmp/t.tar.gz" \
        https://github.com/tmux/tmux/releases/download/3.5a/tmux-3.5a.tar.gz \
        || die "failed to download tmux 3.5a"
    mkdir -p "$dir"
    tar -C "$tmp" -xzf "$tmp/t.tar.gz"
    # shellcheck disable=SC2016  # path expansion must happen at build time
    ( cd "$tmp/tmux-3.5a" \
        && ./configure --prefix="$dir" --enable-utf8proc >/dev/null 2>&1 \
        && make -j >/dev/null 2>&1 \
        && make install >/dev/null 2>&1 ) \
        || die "tmux 3.5a build failed"
    rm -rf "$tmp"
}

install_tmux() {
    if command -v tmux >/dev/null 2>&1 || pkg_installed tmux; then
        log "tmux already installed"
    else
        log "Installing tmux ($PKG)..."
        if [ "$PKG" = brew ]; then
            run brew install tmux
        else
            # ncurses-term provides the tmux-256color terminfo entry that
            # tmux.conf's default-terminal relies on (absent from ncurses-base)
            run $SUDO apt-get install -y tmux ncurses-term
        fi
    fi
    # tmux.conf requires >= 3.3 (allow-passthrough)
    local ver
    ver="$(tmux -V | grep -oE '[0-9]+\.[0-9a-z]+')"
    if [ "$(printf '%s\n3.3\n' "$ver" | sort -V | head -1)" != "3.3" ]; then
        warn "tmux $ver found; tmux.conf needs >= 3.3. Upgrade hints in README.md."
    else
        log "tmux $ver OK"
    fi
    # macOS: pin 3.5a. Newer releases (3.7c verified) cause rendering
    # artifacts over SSH to Termius/iPad — random jitter on any pane repaint
    # and gray flash rectangles at scroll boundaries. Details: README.md.
    if [ "$OS" = Darwin ] && [ "$ver" != "3.5a" ]; then
        if [ -x "$HOME/.local/opt/tmux-3.5a/bin/tmux" ]; then
            log "pinned tmux 3.5a already present"
        else
            build_tmux_pinned_macos
        fi
        mkdir -p "$HOME/.local/bin"
        ln -sf "$HOME/.local/opt/tmux-3.5a/bin/tmux" "$HOME/.local/bin/tmux"
        log "tmux pinned to $("$HOME/.local/opt/tmux-3.5a/bin/tmux" -V) via ~/.local/bin (shadows brew)"
    fi
}

install_nvim() {
    command -v nvim >/dev/null 2>&1 && { log "nvim already installed: $(nvim --version | head -1)"; return; }
    if [ "$PKG" = brew ]; then
        log "Installing neovim (brew)..."
        run brew install neovim
    else
        # Distro packages are years behind; use official tarball + symlink.
        local optdir bin tarball url tmp
        optdir="$HOME/.local/opt"
        bin="$HOME/.local/bin/nvim"
        tarball="nvim-linux-${ARCH}.tar.gz"
        url="https://github.com/neovim/neovim/releases/latest/download/${tarball}"
        log "Installing nvim from official tarball..."
        run mkdir -p "$optdir" "$HOME/.local/bin"
        if $DRY_RUN; then
            echo "[dry-run] would download $url and symlink into ~/.local/bin"
            return
        fi
        tmp="$(mktemp -d)"
        curl "${CURL_ARGS[@]+${CURL_ARGS[@]}}" -fsSL --output "$tmp/$tarball" "$url" \
            || die "failed to download $url"
        tar -C "$optdir" -xzf "$tmp/$tarball"
        ln -sf "$optdir/nvim-linux-${ARCH}/bin/nvim" "$bin"
        rm -rf "$tmp"
    fi
}

install_jq() {
    command -v jq >/dev/null 2>&1 && { log "jq already installed"; return; }
    log "Installing jq ($PKG)..."
    if [ "$PKG" = brew ]; then run brew install jq; else run $SUDO apt-get install -y jq; fi
}

install_yazi() {
    command -v yazi >/dev/null 2>&1 && { log "yazi already installed: $(yazi --version 2>/dev/null | head -1)"; return; }
    if [ "$PKG" = apt ]; then
        pkg_installed unzip || run $SUDO apt-get install -y unzip
    fi
    # Official release tarballs: brew has no bottles for older macOS and no
    # apt package exists — this pattern is instant and identical everywhere.
    case "$OS/$ARCH" in
        Darwin/x86_64) asset="yazi-x86_64-apple-darwin.zip" ;;
        Darwin/arm64)  asset="yazi-aarch64-apple-darwin.zip" ;;
        Linux/x86_64)  asset="yazi-x86_64-unknown-linux-gnu.zip" ;;
        Linux/arm64)   asset="yazi-aarch64-unknown-linux-gnu.zip" ;;
        *) die "unsupported platform for yazi: $OS/$ARCH" ;;
    esac
    log "Installing yazi from official tarball..."
    if $DRY_RUN; then
        echo "[dry-run] would download latest sxyazi/yazi asset $asset, unzip into ~/.local/opt/yazi and symlink yazi+ya"
        return
    fi
    local url tmp optdir
    optdir="$HOME/.local/opt/yazi"
    url="https://github.com/sxyazi/yazi/releases/latest/download/${asset}"
    tmp="$(mktemp -d)"
    curl "${CURL_ARGS[@]+"${CURL_ARGS[@]}"}" -fsSL --output "$tmp/yazi.zip" "$url" \
        || die "failed to download $url"
    rm -rf "$optdir" && mkdir -p "$optdir"
    unzip -q -o "$tmp/yazi.zip" -d "$tmp/x"
    cp -R "$tmp/x/"yazi-*/ "$optdir/"
    ln -sf "$optdir/yazi" "$HOME/.local/bin/yazi"
    ln -sf "$optdir/ya" "$HOME/.local/bin/ya"
    rm -rf "$tmp"
}

install_lazydocker() {
    if ! command -v docker >/dev/null 2>&1; then
        log "no docker found — skipping lazydocker"
        return
    fi
    command -v lazydocker >/dev/null 2>&1 && { log "lazydocker already installed"; return; }
    # Release assets embed the version, so resolve the latest tag first
    # (jq is installed earlier in tools_main).
    local ver asset url tmp optdir
    ver="$(curl "${CURL_ARGS[@]+"${CURL_ARGS[@]}"}" -fsSL \
        https://api.github.com/repos/jesseduffield/lazydocker/releases/latest \
        | jq -r .tag_name | sed 's/^v//')" || die "failed to resolve lazydocker version"
    case "$OS/$ARCH" in
        Darwin/x86_64) asset="lazydocker_${ver}_Darwin_x86_64.tar.gz" ;;
        Darwin/arm64)  asset="lazydocker_${ver}_Darwin_arm64.tar.gz" ;;
        Linux/x86_64)  asset="lazydocker_${ver}_Linux_x86_64.tar.gz" ;;
        Linux/arm64)   asset="lazydocker_${ver}_Linux_arm64.tar.gz" ;;
        *) die "unsupported platform for lazydocker: $OS/$ARCH" ;;
    esac
    log "Installing lazydocker $ver from official tarball..."
    if $DRY_RUN; then
        echo "[dry-run] would download jesseduffield/lazydocker asset $asset -> ~/.local/opt/lazydocker and symlink into ~/.local/bin"
        return
    fi
    url="https://github.com/jesseduffield/lazydocker/releases/download/v${ver}/${asset}"
    tmp="$(mktemp -d)"
    optdir="$HOME/.local/opt/lazydocker"
    curl "${CURL_ARGS[@]+"${CURL_ARGS[@]}"}" -fsSL --output "$tmp/ld.tar.gz" "$url" \
        || die "failed to download $url"
    rm -rf "$optdir" && mkdir -p "$optdir"
    tar -xzf "$tmp/ld.tar.gz" -C "$optdir" lazydocker
    ln -sf "$optdir/lazydocker" "$HOME/.local/bin/lazydocker"
    rm -rf "$tmp"
}

install_fonts() {
    # JetBrainsMono Nerd Font — icons for nvim/tmux/yazi
    if [ "$PKG" = brew ]; then
        if ls "$HOME/Library/Fonts"/JetBrainsMonoNerdFont* >/dev/null 2>&1 \
            || ls /Library/Fonts/JetBrainsMonoNerdFont* >/dev/null 2>&1; then
            log "JetBrains Mono Nerd Font already present"
            return
        fi
        command -v brew >/dev/null 2>&1 \
            || { warn "no Homebrew — install a Nerd Font manually"; return; }
        log "Installing JetBrains Mono Nerd Font (cask)..."
        run brew install --cask font-jetbrains-mono-nerd-font
    else
        local fdir="$HOME/.local/share/fonts/JetBrainsMono"
        if [ -d "$fdir" ] && [ -n "$(ls -A "$fdir" 2>/dev/null)" ]; then
            log "JetBrains Mono Nerd Font already present"
            return
        fi
        pkg_installed fontconfig || run $SUDO apt-get install -y fontconfig
        log "Installing JetBrains Mono Nerd Font..."
        if $DRY_RUN; then
            echo "[dry-run] download JetBrainsMono.zip -> $fdir + fc-cache"
            return
        fi
        local tmp
        tmp="$(mktemp -d)"
        curl "${CURL_ARGS[@]+"${CURL_ARGS[@]}"}" -fsSL --output "$tmp/nf.zip" \
            https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
            || die "failed to download nerd font"
        mkdir -p "$fdir"
        unzip -q -o "$tmp/nf.zip" -d "$fdir"
        rm -rf "$tmp"
        fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
    fi
}

install_opencode_bin() {
    command -v opencode >/dev/null 2>&1 && { log "opencode already installed: $(opencode --version 2>/dev/null || echo '?')"; return; }
    # --no-modify-path is essential: PATH lives in our bashrc, and the installer
    # must not write into the symlinked ~/.bashrc.
    log "Installing opencode (--no-modify-path)..."
    if $DRY_RUN; then
        echo "[dry-run] curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path"
        return
    fi
    curl "${CURL_ARGS[@]+${CURL_ARGS[@]}}" -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
}

tools_main() {
    log "Detected platform: $OS ($ARCH), package manager: $PKG"
    install_gh
    install_tmux
    install_nvim
    install_jq
    install_yazi
    install_lazydocker
    install_fonts
    install_opencode_bin
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_common_args "$@"
    detect_platform
    tools_main
fi

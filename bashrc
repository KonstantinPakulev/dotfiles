# shellcheck shell=bash
# Managed by dotfiles (github.com/KonstantinPakulev/dotfiles)

# PATH: prepend only when not already first. Keeps our tools (pinned tmux,
# tarball nvim, yazi) shadowing system copies while staying idempotent when
# nested shells re-source this file over an inherited environment.
case "$PATH" in
    "$HOME/.local/bin":*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
case "$PATH" in
    "$HOME/.opencode/bin":*) ;;
    *) export PATH="$HOME/.opencode/bin:$PATH" ;;
esac

# tmux derives a client's UTF-8 support from the login shell's locale.
# Stock macOS sshd sessions start with none (Darwin has no locale
# infrastructure), so tmux transcodes every non-ASCII glyph to '_'.
[ -n "${LANG:-}" ] || export LANG=en_US.UTF-8

# Homebrew ncurses: terminfo entries (tmux-*) missing from the macOS system db
for _d in /usr/local/opt/ncurses/bin /opt/homebrew/opt/ncurses/bin; do
    [ -d "$_d" ] && PATH="$_d:$PATH" && break
done
unset _d

# nvim resolves TERM=tmux-256color via terminfo; macOS ships no such entry,
# which degrades pane capabilities inside tmux. Seed a user-local copy from
# Homebrew's db. Idempotent. tic stores entries under hashed dirs
# (~/.terminfo/74/ for "t"), so check both layouts.
if [ "$(uname -s)" = Darwin ] \
    && [ ! -e "$HOME/.terminfo/tmux-256color" ] \
    && [ ! -e "$HOME/.terminfo/74/tmux-256color" ]; then
    for _d in /usr/local/opt/ncurses /opt/homebrew/opt/ncurses; do
        [ -x "$_d/bin/infocmp" ] && [ -x "$_d/bin/tic" ] || continue
        _src="$(mktemp)"
        "$_d/bin/infocmp" -x tmux-256color > "$_src" 2>/dev/null \
            && mkdir -p "$HOME/.terminfo" \
            && "$_d/bin/tic" -x -o "$HOME/.terminfo" "$_src" 2>/dev/null
        rm -f "$_src"
        break
    done
    unset _d _src
fi

# Universal interactive baseline: history, completion, prompt, core aliases.
# Fully skipped for non-interactive shells — zero stdout either way, so
# piping this file's side effects through ssh/scp/rsync stays safe.
case $- in
*i*)
    HISTCONTROL=ignoreboth
    HISTSIZE=1000
    HISTFILESIZE=2000
    shopt -s histappend checkwinsize

    if ! shopt -oq posix; then
        # shellcheck disable=SC1091  # distro paths, guarded above
        [ -f /usr/share/bash-completion/bash_completion ] \
            && . /usr/share/bash-completion/bash_completion
        # shellcheck disable=SC1091
        [ -f /etc/bash_completion ] && . /etc/bash_completion
    fi

    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
    case "$TERM" in xterm*|rxvt*)
        PS1="\[\e]0;\u@\h: \w\a\]$PS1"
        ;;
    esac

    if command -v dircolors >/dev/null 2>&1; then
        eval "$(dircolors -b)" 2>/dev/null || true
        alias ls='ls --color=auto'
        alias grep='grep --color=auto'
    fi
    alias ll='ls -alF'
    alias la='ls -A'
    alias l='ls -CF'

    # Personal aliases and extensions (file absence is normal).
    if [ -f "$HOME/.bash_aliases" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.bash_aliases"
    fi
    ;;
esac

# Machine-local overrides (gitignored, never committed); absence is normal.
# Deliberately OUTSIDE the interactive guard: locals may carry env needed by
# non-login shells too (e.g. apio's /snap/bin insurance).
if [ -f "$HOME/.bashrc.local" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.bashrc.local"
fi

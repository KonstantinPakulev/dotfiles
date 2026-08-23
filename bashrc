# shellcheck shell=bash
# Managed by dotfiles (github.com/KonstantinPakulev/dotfiles)

export PATH="$HOME/.local/bin:$PATH"

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

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

# Machine-local overrides (gitignored, never committed); absence is normal.
# shellcheck disable=SC1091
[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"

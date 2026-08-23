# Managed by dotfiles (github.com/KonstantinPakulev/dotfiles)

# Load shared bashrc (PATH, tools)
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

# Per-machine extras (nvm, pyenv, project PATHs) — gitignored, never committed
[ -f "$HOME/.bash_profile.local" ] && . "$HOME/.bash_profile.local"

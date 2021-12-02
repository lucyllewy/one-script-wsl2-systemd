function is_wsl() {
    [ -n "$WSL_DISTRO_NAME" ] && return 0 || return 1
}

if is_wsl; then
    for sock in "$HOME/.gnupg/S.gpg-agent" "/run/user/$UID/gnupg/S.gpg-agent"; do
        rm -f "$sock"
    done
    unset sock

    mkdir -p "$HOME/.wsl-cmds"
    ln -sf "$(wslpath "$(wslvar 'ProgramFiles(x86)')/GnuPG/bin/gpg.exe")" "$HOME/.wsl-cmds/gpg"

    [[ "$PATH" != *"$HOME/.wsl-cmds"* ]] && export PATH="$HOME/.wsl-cmds:$PATH"
fi

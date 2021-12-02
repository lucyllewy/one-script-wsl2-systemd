function is_wsl() {
    [ -n "$WSL_DISTRO_NAME" ] && return 0 || return 1
}

if is_wsl && command -v socat > /dev/null; then
    rm -f "$HOME/.ssh/agent.sock"

    mkdir -p "$HOME/.wsl-cmds"
    ln -sf "$(wslpath "$(wslvar 'SystemRoot')/System32/OpenSSH/scp.exe")" "$HOME/.wsl-cmds/scp"
    ln -sf "$(wslpath "$(wslvar 'SystemRoot')/System32/OpenSSH/sftp.exe")" "$HOME/.wsl-cmds/sftp"
    ln -sf "$(wslpath "$(wslvar 'SystemRoot')/System32/OpenSSH/ssh.exe")" "$HOME/.wsl-cmds/ssh"
    ln -sf "$(wslpath "$(wslvar 'SystemRoot')/System32/OpenSSH/ssh-add.exe")" "$HOME/.wsl-cmds/ssh-add"

    [[ "$PATH" != *"$HOME/.wsl-cmds"* ]] && export PATH="$HOME/.wsl-cmds:$PATH"
fi

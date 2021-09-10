function is_wsl() {
    [ -n "$WSL_DISTRO_NAME" ] && return 0 || return 1
}

if is_wsl && command -v socat > /dev/null; then
    relayexe="$(wslpath '__RELAY_EXE__')"
    export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
    if ! ps -eo args= | grep -q "^socat UNIX-LISTEN:$SSH_AUTH_SOCK"; then
        rm -f "$SSH_AUTH_SOCK"
        setsid --fork socat UNIX-LISTEN:"$SSH_AUTH_SOCK,fork" EXEC:"$relayexe -ei -ep -s //./pipe/openssh-ssh-agent",nofork
    fi
    unset relayexe
fi

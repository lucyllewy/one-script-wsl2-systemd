function is_wsl() {
    [ -n "$WSL_DISTRO_NAME" ] && return 0 || return 1
}

if is_wsl; then
    relayexe="$(wslpath '$relayexe')"
    for sock in "$HOME/.gnupg/S.gpg-agent" "/run/user/$UID/gnupg/S.gpg-agent"; do
        if ! ps -eo args= | grep -q "^socat UNIX-LISTEN:$sock"; then
            rm -f "$sock"
            mkdir -p "$(dirname "$sock")"
            setsid --fork socat UNIX-LISTEN:"$sock,fork" EXEC:"$relayexe -ei -ep -s -a '$gpgsock'",nofork
        fi
    done
    unset sock

    export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
    if ! ps -eo args= | grep -q "^socat UNIX-LISTEN:$SSH_AUTH_SOCK"; then
        rm -f "$SSH_AUTH_SOCK"
        setsid --fork socat UNIX-LISTEN:"$SSH_AUTH_SOCK,fork" EXEC:"$relayexe -ei -ep -s //./pipe/openssh-ssh-agent",nofork
    fi
    unset relayexe
fi

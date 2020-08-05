function is_wsl() {
    [ -n "$WSL_DISTRO_NAME" ] && return 0 || return 1
}

if is_wsl; then
    relayexe="$(wslpath '__RELAY_EXE__')"
    for sock in "$HOME/.gnupg/S.gpg-agent" "/run/user/$UID/gnupg/S.gpg-agent"; do
        if ! ps -eo args= | grep -q "^socat UNIX-LISTEN:$sock"; then
            rm -f "$sock"
            mkdir -p "$(dirname "$sock")"
            setsid --fork socat UNIX-LISTEN:"$sock,fork" EXEC:"$relayexe -ei -ep -s -a '__GPG_SOCK__'",nofork
        fi
    done
    unset sock
    unset relayexe
fi

SYSTEMD_EXE="$(command -v systemd)"

if [ -z "$SYSTEMD_EXE" ]; then
        if [ -x "/usr/lib/systemd/systemd" ]; then
                SYSTEMD_EXE="/usr/lib/systemd/systemd"
        else
                SYSTEMD_EXE="/lib/systemd/systemd"
        fi
fi

SYSTEMD_EXE="$SYSTEMD_EXE --unit=multi-user.target" # snapd requires multi-user.target not basic.target
SYSTEMD_PID="$(ps -C systemd -o pid= | head -n1)"

if [ -z "$SYSTEMD_PID" ] || [ "$SYSTEMD_PID" -ne 1 ]; then
        if [ -z "$SUDO_USER" ]; then
                [ -f "$HOME/.systemd.env" ] && rm $HOME/.systemd.env
                export > $HOME/.systemd.env
        fi

        if [ "$USER" != "root" ]; then
                case "$0" in
                        *"bash")
                                exec sudo /bin/sh "$(realpath "${BASH_SOURCE[0]}")"
                                ;;
                        *"zsh")
                                exec sudo /bin/sh "$(realpath "${(%):-%x}")"
                                ;;
                        *"ksh")
                                exec sudo /bin/sh "$(realpath "${.sh.file}")"
                                ;;
                        *)
                                exec sudo /bin/sh "$(realpath /etc/profile.d/00-wsl2-systemd.sh)"
                                ;;
                esac
        fi

        if ! grep -q WSL_INTEROP /etc/environment; then
                echo "WSL_INTEROP='/run/WSL/$(ls -rv /run/WSL | head -n1)'" >> /etc/environment
        else
                sed -i "s|WSL_INTEROP=.*|WSL_INTEROP='/run/WSL/$(ls -rv /run/WSL | head -n1)'|" /etc/environment
        fi
        if [ -z "$DISPLAY" ]; then
                echo "DISPLAY='$(awk '/nameserver/ { print $2 }' /etc/resolv.conf)':0" >> /etc/environment
        else
                sed -i '/DISPLAY=.*/d' /etc/environment
        fi
        # Check that /mnt/wslg/.X11-unix exists AND either /tmp/.X11-unix does not exist, or is a directory and is empty
        if [ -d /mnt/wslg/.X11-unix ] && ( [ ! -e /tmp/.X11-unix ] || ( [ -d /tmp/.X11-unix ] && [ $(ls /tmp/.X11-unix | wc -l) -eq 0 ] ) ); then
                rmdir /tmp/.X11-unix
                ln -sf /mnt/wslg/.X11-unix /tmp/
        fi

        if [ -z "$SYSTEMD_PID" ]; then
                env -i /usr/bin/unshare --fork --mount-proc --pid -- sh -c "
                        mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
                        exec $SYSTEMD_EXE
                        " &
                while [ -z "$SYSTEMD_PID" ]; do
                        SYSTEMD_PID="$(ps -C systemd -o pid= | head -n1)"
                        sleep 1
                done
        fi

        exec /usr/bin/nsenter --mount --pid --target "$SYSTEMD_PID" -- su - "$SUDO_USER"
fi

unset SYSTEMD_EXE
unset SYSTEMD_PID

if [ -f "$HOME/.systemd.env" ]; then
        source "$HOME/.systemd.env"
        rm $HOME/.systemd.env
fi

if [ -d "$HOME/.wslprofile.d" ]; then
        for script in "$HOME/.wslprofile.d/"*; do
                source "$script"
        done
        unset script
fi

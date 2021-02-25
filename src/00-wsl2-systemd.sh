if [ "$(ps -c -p 1 -o command=)" != "systemd" ]; then
        if [ -z "$SUDO_USER" ]; then
                export > "$HOME/.profile-systemd"
        fi

        if [ "$USER" != "root" ]; then
                exec sudo /bin/sh "/etc/profile.d/00-wsl2-systemd.sh"
        fi

        if ! grep -q WSL_INTEROP /etc/environment; then
                echo "WSL_INTEROP='/run/WSL/$(ls -rv /run/WSL | head -n1)'" >> /etc/environment
        else
                sed -i "s|WSL_INTEROP=.*|WSL_INTEROP='/run/WSL/$(ls -rv /run/WSL | head -n1)'|" /etc/environment
        fi

        if ! grep -q DISPLAY /etc/environment; then
                echo "DISPLAY='$(awk '/nameserver/ { print $2 }' /etc/resolv.conf):0'" >> /etc/environment
        else
                sed -i "s|DISPLAY=.*|DISPLAY='$(awk '/nameserver/ { print $2 }' /etc/resolv.conf):0'|" /etc/environment
        fi

        exec /usr/bin/nsenter --mount --pid --target "$(ps -C systemd -o pid= | head -n1)" -- su - "$SUDO_USER"
fi

if [ -f "$HOME/.profile-systemd" ]; then
        source "$HOME/.profile-systemd"
fi

if [ -d "$HOME/.wslprofile.d" ]; then
        for script in "$HOME/.wslprofile.d/"*; do
                source "$script"
        done
        unset script
fi

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
		[ -f "$HOME/.systemd.env" ] && rm "$HOME/.systemd.env"
		export > "$HOME/.systemd.env"
	fi

	if [ "$USER" != "root" ]; then
		case "$0" in
			*"zsh")
				WSL_SYSTEMD_EXECUTION_ARGS="$ZSH_EXECUTION_STRING"
				;;
			*)
				WSL_SYSTEMD_EXECUTION_ARGS="$@"
				;;
		esac
		export WSL_SYSTEMD_EXECUTION_ARGS
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
		if [ -f "/tmp/.X11-unix/X0" ]; then
			echo "DISPLAY=:0" >> /etc/environment
		else
			echo "DISPLAY=$(awk '/nameserver/ { print $2":0" }' /etc/resolv.conf)" >> /etc/environment
		fi
	else
		sed -i "/DISPLAY=.*/d" /etc/environment
		echo "DISPLAY='$DISPLAY'" >> /etc/environment
	fi

	if [ -z "$SYSTEMD_PID" ]; then
		env -i /usr/bin/unshare --fork --mount-proc --pid --propagation shared -- sh -c "
			mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
			exec $SYSTEMD_EXE
			" &
		while [ -z "$SYSTEMD_PID" ]; do
			SYSTEMD_PID="$(ps -C systemd -o pid= | head -n1)"
			sleep 1
		done

		while [ "$(/usr/bin/nsenter --mount --pid --target "$SYSTEMD_PID" -- systemctl is-system-running)" = "starting" ]; do
			sleep 1
		done
	fi

	exec /usr/bin/nsenter --mount --pid --target "$SYSTEMD_PID" -- machinectl shell -q "$SUDO_USER"@.host $WSL_SYSTEMD_EXECUTION_ARGS
fi

unset SYSTEMD_EXE
unset SYSTEMD_PID

if [ -f "$HOME/.systemd.env" ]; then
	source "$HOME/.systemd.env"
	rm "$HOME/.systemd.env"
fi

cd "$PWD"

if [ -d "$HOME/.wslprofile.d" ]; then
	for script in "$HOME/.wslprofile.d/"*; do
		source "$script"
	done
	unset script
fi

if [ ! -d /sys/kernel/security/apparmor ]; then
    mount -t securityfs securityfs /sys/kernel/security
fi

if [ -d /sys/kernel/security/apparmor/policy/namespaces ]; then
    mkdir -p /sys/kernel/security/apparmor/policy/namespaces/osws-"$WSL_DISTRO_NAME"
fi

/usr/bin/env -i /usr/bin/unshare --fork --mount --propagation shared --mount-proc --pid -- \
 sh -c '
 SYSTEMDCMD=
 if [ -d /sys/module/apparmor ]; then
    SYSTEMDCMD='"'"'aa-exec -n osws-'"$WSL_DISTRO_NAME"' -p unconfined --'"'"'
 fi
 mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc; [ -x /usr/lib/systemd/systemd ] && \
 exec $SYSTEMDCMD /usr/lib/systemd/systemd --unit=multi-user.target \
 || exec /lib/systemd/systemd --unit=multi-user.target'
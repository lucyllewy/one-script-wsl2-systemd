## About

This repository includes the files to set-up WSL2 distro to run systemd.

### What does it do

#### In WSL2
- Install a script that starts systemd inside a process namespace so that it gets PID 1.
- Install a sudoers configuration file that allows the script to call itself as root without requring setuid.
- Install GPG and SSH agent relays to Windows equivalents.
- Install WSLUtilities
- Configure your WSL sessions to connect to an X11 server in Windows, or use WSLg if it is available on your system.
- Configure xdg-open to open files and addresses in Windows

#### In Windows
- Install GPG4Win via winget.exe, which is available in the latest dev branch of Windows 10 Insider Preview. (disable this with `-NoGPG`)
- Add a scheduled task that launches when you login to Windows to start the GPG-Agent from GPG4Win
- Install a custom WSL kernel based on the Microsoft sources with AppArmor added to support [Snap Package](https://snapcraft.io) strict confinement. (disable this with `-NoKernel`)
- Add a scheduled task that launches when you login to Windows to update the custom kernel when a new release is made.
- Enable and start the in-built Windows SSH-Agent service.

## Installing

1. Run `Install-Module -Scope CurrentUser Wsl` to install the required PowerShell module
1. Download the `install.ps1` script
1. Open a PowerShell or CMD window: press `Win + x` then choose either "Command Prompt" or "Windows PowerShell" depending on which your system presents in the menu
1. Run the following command in the PowerShell Core or CMD window to set up your default distro (make sure to replace `powershell.exe` with `pwsh.exe` if you're using PowerShell Core):
    ```powershell
    pwsh.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File \path\to\install.ps1
    ```
If you want to skip the GPG4Win installation, use the flag `-NoGPG`

You can also specify a distro name with the `-distro` flag, e.g:

```powershell
pwsh.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File \path\to\install.ps1 -distro Ubuntu-20.04
```
You will find all the available distros on your system when executing `wsl.exe --list --all` in command prompt

Currently supported distros:
- Ubuntu
- Kali Linux
- Debian
- Alpine
- OpenSUSE
- Any other linux distribution with `apt-get` or `zypper` as package manager

## Minimal manual installation

To manually install the bare-minimum setup, i.e. without using the PowerShell script, follow the procedure below:

1. Edit or create the config file at `/etc/wsl.conf` to add the following content:
   ```ini
   [boot]
   command = "/usr/bin/env -i /usr/bin/unshare --fork --mount-proc --pid -- sh -c 'mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc; [ -x /usr/lib/systemd/systemd ] && exec /usr/lib/systemd/systemd --unit=multi-user.target || exec /lib/systemd/systemd --unit=multi-user.target'"
   ```
1. Copy `src/sudoers` to `/etc/sudoers.d/wsl2-systemd`.
1. Copy `src/00-wsl2-systemd.sh` to `/etc/profile.d/00-wsl2-systemd.sh`.
1. Ensure that your user account is a member of the `sudo` group, or change `%sudo` in `/etc/sudoers.d/wsl2-systemd` to an alternative group name of which your account is a member.
1. Exit any active terminal sessions that are using your distro.
1. Use `wsl.exe` via powershell to terminate/shutdown your distro so that the `wsl.conf` settings are applied.
   ```powershell
   wsl.exe --terminate ubuntu
   ```

## Alternatives

- [Damion Gans' installer for the two-script variant](https://github.com/damionGans/ubuntu-wsl2-systemd-script/)
- [Genie](https://github.com/arkane-systems/genie)
- [My 'change the user shell' variant that supports zsh and fish](https://github.com/diddlesnaps/chsh-variant-wsl2-systemd) I do not keep the change the user shell variant updated so it is likely all sorts of broken.

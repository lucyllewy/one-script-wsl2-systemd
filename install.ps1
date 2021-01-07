param($Distro, $User, [switch]$NoGPG)

$repoUrl = 'https://github.com/diddlesnaps/one-script-wsl2-systemd/raw/master/'

# The main files to install.
$files = @{
    'systemd' = @{
        'source' = 'src/00-wsl2-systemd.sh';
        'dest' = '/etc/profile.d/00-wsl2-systemd.sh';
        'errorIsFatal' = $true;
        'errorMessage' = 'Could not fetch the systemd script. Aborting installation.';
        'user' = 'root'
    };
    'sudoers' = @{
        'source' = 'src/sudoers';
        'dest' = '/etc/sudoers.d/wsl2-systemd';
        'errorIsFatal' = $true;
        'errorMessage' = 'Could not fetch the sudoers file. Aborting installation.';
        'user' = 'root'
    };
    'wslview-desktop' = @{
        'source' = 'src/applications/wslview.desktop';
        'dest' = '/usr/share/applications/wslview.desktop';
        'errorIsFatal' = $false;
        'errorMessage' = '';
        'user' = 'root'
    }
}

# These depend on the npiperelay.exe so we include them separately.
$agentfiles = @{
    'gpg-agent.sh' = @{
        'source' = 'src/profile.d/gpg-agent.sh';
        'dest' = '$HOME/.wslprofile.d/gpg-agent.sh'
        'errorMessage' = 'Could not fetch the GPG agent script. Continuing without it.'
    };
    'ssh-agent.sh' = @{
        'source' = 'src/profile.d/ssh-agent.sh';
        'dest' = '$HOME/.wslprofile.d/ssh-agent.sh'
        'errorMessage' = 'Could not fetch the SSH agent script. Continuing without it.'
    }
}

$npiperelayUrl = 'https://github.com/NZSmartie/npiperelay/releases/download/v0.1/npiperelay.exe'

[string[]]$wslparams = $null
if ($Distro) {
    $wslparams += '--distribution', $Distro
} else {
    $Distro = 'your default distro'
}

function Invoke-WslCommand($User, $Command) {
    $params = $wslparams
    if ($User) {
        $params += '--user', $User
    }
    $params += '-e', 'sh'
    "$Command`nexit;".Replace("`r`n", "`n") | & wsl.exe $params
}

function Add-WslFile($User, $Uri, $File, $Replacements) {
    if ($Uri -and $File) {
        $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            if ($response.Headers['Content-Type'] -eq 'application/octet-stream') {
                $content = [Text.Encoding]::UTF8.GetString($response.content)
            } else {
                $content = $response.Content
            }
            if ($Replacements) {
                $Replacements.keys | ForEach-Object {
                    $content = $content.Replace($_, $relayexe).Replace($Replacements[$_], $gpgsock)
                }
            }
            Invoke-WslCommand -User $User -Command "
mkdir -p `"`$(dirname `"$File`")`"
cat > `"$File`" <<'EOF'
$content
EOF
"
        } else {
            Write-Output $response.StatusCode
            throw
        }
    }
}

function Add-WslFiles($Files, $Replacements) {
    if ($Files) {
        $Files.values | ForEach-Object {
            $file = $_
            try {
                Add-WslFile -User $file.user -Uri ($repoUrl + $file.source) -File $file.dest -Replacements $Replacements
            } catch {
                write-output $_
                if ($file.errorIsFatal) {
                    Abort-Installation
                    throw $file.errorMessage
                } else {
                    Write-Warning -Message $file.errorMessage
                }
            }
        }
    }
}

function Abort-Installation {
    $files.values + $agentfiles.values | ForEach-Object {
        $remove = $_.dest
        if ($_.user) {
            $wslUser = $_.user
        } else {
            $wslUser = $User
        }
        Invoke-WslCommand -User $wslUser -Command "rm -f $remove"
    }
}

Write-Output "--- Installing files in $Distro"
Add-WslFiles -Files $files

# Fetch agent sockets relay
Write-Output "--- Installing SSH, GPG, etc. agent scripts in $Distro"
$gpgsock = "$env:APPDATA/gnupg/S.gpg-agent".replace('\', '/')
$relayexe = "$env:APPDATA/wsl2-ssh-gpg-agent-relay.exe".replace('\', '/')
$relayResponse = Invoke-WebRequest -Uri $npiperelayUrl -UseBasicParsing -OutFile $relayexe -PassThru

if ($relayResponse.StatusCode -eq 200) {
    # Setup agent sockets
    Add-WslFiles -Files $agentfiles -Replacements @{ '__RELAY_EXE__' = $relayexe; '__GPG_SOCK__' = $gpgsock }
} else {
    Write-Warning -Message 'Could not fetch the SSH, GPG, etc. agent relay proxy executable. Continuing without it.'
}

# Disable some systemd units that conflict with our setup
Write-Output "--- Disabling conflicting systemd services in $distro"
Invoke-WslCommand -User 'root' -Command 'rm -f /etc/systemd/user/sockets.target.wants/dirmngr.socket'
Invoke-WslCommand -User 'root' -Command 'rm -f /etc/systemd/user/sockets.target.wants/gpg-agent*.socket'

# Update the desktop mime database
Write-Output "--- Updating desktop-file MIME database in $distro"
Invoke-WslCommand -User 'root' -Command @'
do_ubuntu() {
    do_apt
}
do_kali() {
    do_apt
}
do_apt() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -yyq desktop-file-utils
}
do_apk() {
    apk update
    apk add desktop-file-utils
}
do_sles() {
    do_zypper
}
do_zypper() {
    zypper --non-interactive install desktop-file-utils
}
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        "ubuntu")
            do_ubuntu ;;
        "kali")
            do_kali ;;
        "debian")
            do_apt ;;
        "alpine")
            do_apk ;;
        "sles")
            do_sles ;;
        *)
            case "$ID_LIKE" in
                *"debian"*)
                    do_apt ;;
                *"suse"*)
                    do_zypper ;;
                *)
            esac
            ;;
    esac
fi
if command -v update-desktop-database >/dev/null; then
    update-desktop-database
fi
'@

Write-Output "--- Installing WSLUtilities in $distro"
Invoke-WslCommand -User 'root' -Command @'
do_ubuntu() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -yyq ubuntu-wsl
}
do_kali() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt install -yyq gnupg2 apt-transport-https
    wget -O - https://access.patrickwu.space/wslu/public.asc | apt-key add -
    echo "deb https://access.patrickwu.space/wslu/kali kali-rolling main" >> /etc/apt/sources.list
    apt-get update
    apt-get install -yyq wslu
}
do_apt() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt install -yyq gnupg2 apt-transport-https
    wget -O - https://access.patrickwu.space/wslu/public.asc | apt-key add -
    echo "deb https://access.patrickwu.space/wslu/debian buster main" >> /etc/apt/sources.list
    apt-get update
    apt-get install -yyq wslu
}
do_apk() {
    echo "@testing https://dl-cdn.alpinelinux.org/alpine/edge/community/" >> /etc/apk/repositories
    apk update
    apk add wslu@testing
}
do_sles() {
    SLESCUR_VERSION="$(grep VERSION= /etc/os-release | sed -e s/VERSION=//g -e s/\"//g -e s/-/_/g)"
    sudo zypper addrepo https://download.opensuse.org/repositories/home:/wslutilities/SLE_$SLESCUR_VERSION/home:wslutilities.repo
    sudo zypper addrepo https://download.opensuse.org/repositories/graphics/SLE_12_SP3_Backports/graphics.repo
    zypper --non-interactive --no-gpg-checks install wslu
}
do_zypper() {
    zypper addrepo https://download.opensuse.org/repositories/home:/wslutilities/openSUSE_Leap_15.1/home:wslutilities.repo
    zypper --non-interactive install wslu
}
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        "ubuntu")
            do_ubuntu ;;
        "kali")
            do_kali ;;
        "debian")
            do_apt ;;
        "alpine")
            do_apk ;;
        "sles")
            do_sles ;;
        *)
            case "$ID_LIKE" in
                *"debian"*)
                    do_apt ;;
                *"suse"*)
                    do_zypper ;;
                *)
            esac
            ;;
    esac
fi
if command -v wslview >/dev/null; then
    wslview --register
fi
'@

# Install GPG4Win
if ($NoGPG) {
    Write-Output 'Skipping Gpg4win installation'
} else {
    Write-Output '--- Installing GPG4Win in Windows'
    winget.exe install --silent gnupg.Gpg4win
}

Write-Output '--- Adding a Windows scheduled tasks and starting services'

$adminScript = "$env:TEMP/wsl2-systemd-services.ps1"
$response = Invoke-WebRequest -Uri ($repoUrl + 'services.ps1') -OutFile $adminScript -PassThru -UseBasicParsing
if ($response.StatusCode -eq 200) {
    Start-Process -Verb RunAs -FilePath powershell.exe -Args '-NonInteractive', '-ExecutionPolicy', 'ByPass', $adminScript
} else {
    Write-Warning 'Could not fetch the script to set up your SSH & GPG Agents and update the custom WSL2 kernel'
}

Write-Output "`nDone."
Write-Output "If you want to go back to the Microsoft kernel open a PowerShell or CMD window and run:"
Write-Output "`n`tpowershell.exe -NonInteractive -NoProfile -Command 'Start-Process' -Verb RunAs -FilePath powershell.exe -ArgumentList { Unregister-ScheduledJob -Name UpdateWSL2CustomKernel }"
Write-Output "`n"

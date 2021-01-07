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

function Get-IniContent($filePath)
{
    $ini = @{}
    switch -regex -file $FilePath
    {
        "^\[(.+)\]" # Section
        {
            $section = $matches[1]
            $ini[$section] = @{}
            $CommentCount = 0
        }
        "^(;.*)$" # Comment
        {
            $value = $matches[1]
            $CommentCount = $CommentCount + 1
            $name = "Comment" + $CommentCount
            $ini[$section][$name] = $value
        }
        "(.+?)\s*=(.*)" # Key
        {
            $name,$value = $matches[1..2]
            $ini[$section][$name] = $value
        }
    }
    return $ini
}

function Write-IniOutput($InputObject)
{
    foreach ($i in $InputObject.keys)
    {
        if (!($($InputObject[$i].GetType().Name) -eq "Hashtable"))
        {
            #No Sections
            Write-Output "$i=$($InputObject[$i])"
        } else {
            #Sections
            Write-Output "[$i]"
            Foreach ($j in ($InputObject[$i].keys | Sort-Object))
            {
                if ($j -match "^Comment[\d]+") {
                    Write-Output "$($InputObject[$i][$j])"
                } else {
                    Write-Output "$j=$($InputObject[$i][$j])"
                }
            }
            Write-Output ""
        }
    }
}

function Add-WslFileContent($DistributionName, $User, $File, $Content) {
    Invoke-WslCommand -DistributionName $DistributionName -User $User -Command "
mkdir -p `"`$(dirname `"$File`")`"
cat > `"$File`" <<'EOF'
$Content
EOF
"
}

function Add-WslFile($DistributionName, $User, $Path, $File, $Replacements) {
    if ($Path -and $File) {
        $Content = ""
        if ($Path.StartsWith("http://") -or $Path.StartsWith("https://")) {
            $response = Invoke-WebRequest -Uri $Path -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                if ($response.Headers['Content-Type'] -eq 'application/octet-stream') {
                    $Content = [Text.Encoding]::UTF8.GetString($response.content)
                } else {
                    $Content = $response.Content
                }
            } else {
                Write-Output $response.StatusCode
                throw
            }
        }
        if ($Content -and $Replacements) {
            $Replacements.keys | ForEach-Object {
                $Content = $Content.Replace($_, $relayexe).Replace($Replacements[$_], $gpgsock)
            }
        }
        if ($Content) {
            Add-WslFileContent -DistributionName $DistributionName -User $User -Content $Content
        }
    }
}

function Add-WslFiles($DistributionName, $Files, $Replacements) {
    if ($Files) {
        $Files.values | ForEach-Object {
            $file = $_
            try {
                Add-WslFile -DistributionName $DistributionName -User $file.user -Path ($repoUrl + $file.source) -File $file.dest -Replacements $Replacements
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
        Invoke-WslCommand -DistributionName $Distro -User $wslUser -Command "rm -f $remove"
    }
}

Write-Output "--- Installing WSL PowerShell module"
Install-Module -Name Wsl
Import-Module -Name Wsl

if (-not $Distro) {
    $Distro = Get-WslDistribution -Default
    Write-Output "--- No distro specified, using your default distro $Distro"
}

Write-Output "--- Installing files in $Distro"
Add-WslFiles -DistributionName $Distro -Files $files

Write-Output "--- Setting systemd to automatically start in $Distro"
$wslconfig = @{}
if (Test-Path("//wsl/$Distro/etc/wsl.conf")) {
    $wslconfig = Get-IniContent "//wsl/$Distro/etc/wsl.conf"
}
if (-not $wslconfig["boot"]) {
    $wslconfig["boot"] = @{}
}
if (-not $wslconfig["boot"]["command"]) {
    $wslconfig["boot"]["command"] = ""
}
$wslconfig.boot.command = "/usr/bin/env -i /usr/bin/unshare --fork --mount-proc --pid -- sh -c 'mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc; [ -x /usr/lib/systemd/systemd ] && exec /usr/lib/systemd/systemd --unit=multi-user.target || exec /lib/systemd/systemd'"
$wslconfig_content = Write-IniOutput $wslconfig

Add-WslFileContent -DistributionName $Distro -User "root" -File "/etc/wsl.conf" -Content $wslconfig_content

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
Invoke-WslCommand -DistributionName $Distro -User 'root' -Command 'rm -f /etc/systemd/user/sockets.target.wants/dirmngr.socket'
Invoke-WslCommand -DistributionName $Distro -User 'root' -Command 'rm -f /etc/systemd/user/sockets.target.wants/gpg-agent*.socket'

# Update the desktop mime database
Write-Output "--- Updating desktop-file MIME database in $distro"
Invoke-WslCommand -DistributionName $Distro -User 'root' -Command @'
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
Invoke-WslCommand -DistributionName $Distro -User 'root' -Command @'
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

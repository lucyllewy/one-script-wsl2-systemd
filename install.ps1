param($distro)

$repoUrl = 'https://github.com/diddlesnaps/one-script-wsl2-systemd/raw/master'
$profilePath = 'src/bash_profile.sh'
$wslScriptPath = 'src/00-wsl2-systemd.sh'
$sudoersPath = 'src/sudoers'

$npiperelayUrl = 'https://github.com/NZSmartie/npiperelay/releases/download/v0.1/npiperelay.exe'

[string[]]$wslparams = $null
if ($distro) {
    $wslparams += '--distribution', $distro
}

function runAsRoot($cmd) {
    runAsUser $cmd 'root'
}
function runAsUser($cmd, $user) {
    $params = $wslparams
    if ($user) {
        $params += '--user', $user
    }
    $params += '-e', 'sh'
    "$cmd`nexit;".Replace("`r`n", "`n") | & wsl.exe $params
}

# Disable some systemd units that conflict with our setup
runAsRoot 'ln -sf /dev/null /etc/systemd/system/proc-sys-fs-binfmt_misc.mount'
runAsRoot 'rm -f /etc/systemd/user/sockets.target.wants/dirmngr.socket'
runAsRoot 'rm -f /etc/systemd/user/sockets.target.wants/gpg-agent*.socket'

# Setup the sudoers access
$sudoersResponse = Invoke-WebRequest -Uri "$repoUrl/$sudoersPath" -UseBasicParsing
if ($sudoersResponse.StatusCode -eq 200) {
    $sudoers = $sudoersResponse.Content
    runAsRoot "cat > /etc/sudoers.d/wsl2-systemd <<-'EOF'
$sudoers
EOF
"
} else {
    Write-Output 'Error: Could not fetch the sudoers file. Quitting.'
    exit
}

# Fetch and install the script
$wslScriptResponse = Invoke-WebRequest -Uri "$repoUrl/$wslScriptPath" -UseBasicParsing
if ($wslScriptResponse.StatusCode -eq 200) {
    $script = $wslScriptResponse.Content
    runAsRoot "cat > /etc/profile.d/00-wsl2-systemd.sh <<-'EOF'
$script
EOF
"
} else {
    Write-Output 'Error: Could not fetch the systemd script. Quitting.'
    exit
}

# Install GPG4Win
winget.exe install gnupg.Gpg4win

# Fetch agent sockets relay
$gpgsock = "$env:APPDATA/gnupg/S.gpg-agent".replace('\', '/')
$relayexe = "$env:APPDATA/wsl2-ssh-gpg-agent-relay.exe".replace('\', '/')
$relayResponse = Invoke-WebRequest -Uri $npiperelayUrl -UseBasicParsing -OutFile $relayexe -PassThru

if ($relayResponse.StatusCode -eq 200) {
    # Setup agent sockets
    $profileResponse = Invoke-WebRequest -Uri "$repoUrl/$profilePath" -UseBasicParsing
    if ($profileResponse.StatusCode -eq 200) {
        $profile = $profileResponse.Content
        runAsUser "cat >> `"`$HOME/.bash_profile`" <<'EOF'

$profile

EOF
"
    } else {
        Write-Output 'Could not fetch the SSH and GPG agent .bash_profile script. Continuing without it.'
    }
} else {
    Write-Output 'Could not fetch the SSH and GPG agent relay proxy executable. Continuing without it.'
}

Using module Wsl

param(
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Distro,

    [switch]
    $LeaveGPG,

    [switch]
    $LeaveKernel
)

$PSDefaultParameterValues['*:Encoding'] = 'utf8'

$rootFiles = @(
    @{ 'dest' = '/etc/profile.d/00-wsl2-systemd.sh' },
    @{ 'dest' = '/etc/sudoers.d/wsl2-systemd' },
    @{ 'dest' = '/usr/share/applications/wslview.desktop' },
    @{ 'dest' = '/etc/systemd/system/user-runtime-dir@.service.d/override.conf' },
    @{ 'dest' = '/etc/systemd/system/wsl2-xwayland.service' },
    @{ 'dest' = '/etc/systemd/system/wsl2-xwayland.socket' }
)
$userFiles = @(
    @{ 'dest' = '/home/*/.wslprofile.d' },
    @{ 'dest' = '/home/*/.wsl-cmds' }
)

function Invoke-WslCommand
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = "DistributionName", Position = 1)]
        [SupportsWildCards()]
        [string[]]$DistributionName,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ParameterSetName = "Distribution")]
        [WslDistribution[]]$Distribution,

        [Parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$User
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq "DistributionName") {
            if ($DistributionName) {
                $Distribution = Get-WslDistribution $DistributionName
            } else {
                $Distribution = Get-WslDistribution -Default
            }
        } elseif ($PSCmdLet.ParameterSetName -ne "Distribution") {
            $Distribution = Get-WslDistribution -Default
        }

        $Distribution | ForEach-Object {
            $DistroName = $_.Name
            $wslargs = @("--distribution", $DistroName)
            if ($User) {
                $wslargs += @("--user", $User)
            }

            $Command = $Command + "`n" # Add a trailing new line
            $Command = $Command.Replace("`r`n", "`n") # Replace Windows newlines with Unix ones
            $Command += '#' # Add a comment on the last line to hide PowerShell cruft added to the end of the string

            if ($PSCmdlet.ShouldProcess($DistroName, "Invoke Command")) {
                $Command | &$wslPath @wslargs /bin/sh
                if ($LASTEXITCODE -ne 0) {
                    # Note: this could be the exit code of wsl.exe, or of the launched command.
                    throw "Wsl.exe returned exit code $LASTEXITCODE from distro: ${DistroName}"
                }    
            }
        }
    }
}

function Add-WslFileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [WslDistribution[]]$Distribution,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$User,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$File
    )

    $commandArgs = @{}
    if ($User) {
        $commandArgs = @{User = $User}
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $base64 = [Convert]::ToBase64String($bytes)

    $Directory = ($File | Split-Path).Replace('\', '/')

    $Command = "mkdir -p `"$Directory`" && echo '$base64' | base64 -d > `"$File`""
    Invoke-WslCommand -Distribution $Distribution @commandArgs -Command $Command
}

function Remove-WslFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        $Files,
    
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [WslDistribution[]]$Distribution,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$User
    )

    process {
        foreach ($file in $Files) {
            $remove = $file.dest
            $commandArgs = @{}
            if ($file['user']) {
                $commandArgs = @{User = $file.user}
            } elseif ($User) {
                $commandArgs = @{User = $User}
            }
            Invoke-WslCommand -Distribution $Distribution -Command "rm -rf $remove" @commandArgs
        }
    }
}

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

function Out-IniFile($InputObject, $FilePath)
{
    $outFile = New-Item -ItemType file -Path $Filepath -Force
    foreach ($i in $InputObject.keys)
    {
        if (!($($InputObject[$i].GetType().Name) -eq "Hashtable"))
        {
            #No Sections
            Add-Content -Path $outFile -Value "$i=$($InputObject[$i])"
        } else {
            #Sections
            Add-Content -Path $outFile -Value "[$i]"
            Foreach ($j in ($InputObject[$i].keys | Sort-Object))
            {
                if ($j -match "^Comment[\d]+") {
                    Add-Content -Path $outFile -Value "$($InputObject[$i][$j])"
                } else {
                    Add-Content -Path $outFile -Value "$j=$($InputObject[$i][$j])"
                }

            }
            Add-Content -Path $outFile -Value ""
        }
    }
}

$powershellProcess = (Get-Process -Id $PID).ProcessName + '.exe'

if (-not [System.Environment]::Is64BitProcess) {
    # Allow launching WSL from 32 bit powershell
    $wslPath = "$env:windir\sysnative\wsl.exe"
} else {
    $wslPath = "$env:windir\system32\wsl.exe"
}

Write-Output "`r`n`n"
Write-Output "#########################################################"
Write-Output "#                                                       #"
Write-Output "#       One Script WSL2 Systemd uninstall script        #"
Write-Output "#                                                       #"
Write-Output "#########################################################`n`n"

if ($PSVersionTable.PSEdition -eq "Core" -and -not $IsWindows) {
    Write-Output "This script must be run in Windows."
    exit
}

if ($Distro -and -not ($Distribution = Get-WslDistribution -Name $Distro)) {
    Write-Error "!!! $Distro is not currently installed. Refusing to continue."
    exit
}
if (-not $Distribution) {
    # Get all distributions except docker-desktop-related
    $Distribution = Get-WslDistribution | Where-Object -Property Name -NotLike -Value "docker-desktop*"
}

Write-Output "---------------------------------------------------------`n`n"

$Distribution | ForEach-Object {
    $DistroName = $_.Name
    Write-Output "Uninstalling systemd enablement from $DistroName"
    Remove-WslFiles -Files $rootFiles -Distribution $_ -User 'root'
    Remove-WslFiles -Files $userFiles -Distribution $_ -User 'root'
    if (Test-Path -Path "$($Distribution.FileSystemPath)\etc\wsl.conf") {
        $wslconfig = Get-IniContent "$($Distribution.FileSystemPath)\etc\wsl.conf"
        if ($wslconfig["boot"] -and $wslconfig.boot.command -eq "/usr/bin/env -i /usr/bin/unshare --fork --mount-proc --pid -- sh -c 'mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc; [ -x /usr/lib/systemd/systemd ] && exec /usr/lib/systemd/systemd --unit=multi-user.target || exec /lib/systemd/systemd --unit=multi-user.target'") {
            $wslconfig.boot.Remove('command')
            (Write-IniOutput $wslconfig) -Join "`n" | Add-WslFileContent -Distribution $Distribution -User "root" -File "/etc/wsl.conf"
        }
    }
}

if (-not $LeaveGPG) {
    Write-Output "Uninstalling GnuPG"
    winget.exe uninstall gnupg.Gpg4win
    Start-Process -Verb RunAs -Wait -FilePath $powershellProcess -Args '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'ByPass', '-Command', "Unregister-ScheduledJob -Name GPGAgent -Force"
}

if (-not $LeaveKernel) {
    Write-Output "Reverting WSL to the Microsoft-provided kernel"
    Start-Process -Verb RunAs -Wait -FilePath $powershellProcess -Args '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'ByPass', '-Command', "Unregister-ScheduledJob -Name UpdateWSL2CustomKernel -Force"
    if (Test-Path -Path "$env:USERPROFILE/.wslconfig") {
        $wslconfig = Get-IniContent "$env:USERPROFILE/.wslconfig"
        $wslconfig["wsl2"].Remove("kernel")
        Out-IniFile $wslconfig "$env:USERPROFILE/.wslconfig"
    }
}

Write-Output "Done."

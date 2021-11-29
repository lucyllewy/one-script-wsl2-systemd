Using module Wsl

$PSDefaultParameterValues['*:Encoding'] = 'utf8'

$rootFiles = @(
    '/etc/profile.d/00-wsl2-systemd.sh',
    '/etc/sudoers.d/wsl2-systemd',
    '/usr/share/applications/wslview.desktop',
    '/etc/systemd/system/user-runtime-dir@.service.d/override.conf',
    '/etc/systemd/system/wsl2-xwayland.service',
    '/etc/systemd/system/wsl2-xwayland.socket'
    )
$userFiles = @(
    '/home/*/.wslprofile.d/gpg-agent.s',
    '/home/*/.wslprofile.d/ssh-agent.sh'
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
            $wslargs = @("--distribution", $_.Name)
            if ($User) {
                $wslargs += @("--user", $User)
            }

            $Command = $Command + "`n" # Add a trailing new line
            $Command = $Command.Replace("`r`n", "`n") # Replace Windows newlines with Unix ones
            $Command += '#' # Add a comment on the last line to hide PowerShell cruft added to the end of the string

            if ($PSCmdlet.ShouldProcess($_.Name, "Invoke Command")) {
                $Command | &$wslPath @wslargs /bin/bash
                if ($LASTEXITCODE -ne 0) {
                    # Note: this could be the exit code of wsl.exe, or of the launched command.
                    throw "Wsl.exe returned exit code $LASTEXITCODE"
                }    
            }
        }
    }
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
            if ($_['user']) {
                $commandArgs = @{User = $file.user}
            } elseif ($User) {
                $commandArgs = @{User = $User}
            }
            Invoke-WslCommand -Distribution $Distribution -Command "rm -f $remove" @commandArgs
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

if (-not $Env:WT_SESSION) {
    if (-not -not $(where.exe wt.exe)) {
        Write-Output "Relaunching in Windows Terminal"
        if (-not -not $(where.exe pwsh.exe)) {
            wt.exe new-tab --startingDirectory=$PWD pwsh.exe -NoExit -NonInteractive -NoProfile $MyInvocation.Line
        } elseif ($PSVersionTable.PSEdition -ne "Core") {
            Write-PowerShellMsg
        }
        exit
    } else {
        Write-Output "The output of this script requires that PowerShell be hosted inside Windows Terminal. Please install Windows Terminal from the Windows Store if it is not already installed, open a new PowerShell Core session in Windows Terminal, and re-run this script there."
        exit
    }
}

if ($PSVersionTable.PSEdition -ne "Core") {
    Write-PowerShellMsg
    exit
}

if (-not $IsWindows) {
    Write-Output "This script must be run in Windows."
    exit
}

Write-Output "---------------------------------------------------------`n`n"

Get-WslDistribution | ForEach-Object {
    Remove-WslFiles -Files $rootFiles -Distribution $_ -User 'root'
    Remove-WslFiles -Files $userFiles -Distribution $_ -User 'root'
    if (Test-Path("$($Distribution.FileSystemPath)\etc\wsl.conf")) {
        $wslconfig = Get-IniContent "$($Distribution.FileSystemPath)\etc\wsl.conf"
        if ($wslconfig["boot"]) {
            $wslconfig.boot.Remove('command')
            (Write-IniOutput $wslconfig) -Join "`n" | Add-WslFileContent -Distribution $Distribution -User "root" -File "/etc/wsl.conf"
        }
    }
}

winget.exe uninstall gnupg.Gpg4win

Start-Process -Verb RunAs -Wait -FilePath $powershellProcess -Args '-NonInteractive', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'ByPass', '-Command', @"
Unregister-ScheduledJob -Name GPGAgent -Force
Unregister-ScheduledJob -Name UpdateWSL2CustomKernel -Force
"@

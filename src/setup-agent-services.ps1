# This script runs as Administrator!

param(
    [switch]
    $NoGPG,

    [switch]
    $NoKernel
)

# Enable and start SSH Agent in Windows
try {
    Set-Service -Name ssh-agent -StartupType Automatic
    Start-Service -Name ssh-agent
} catch {
    Write-Output $_
}

# Add startup task for GPG Agent in Windows
try {
    Unregister-ScheduledJob -Name GPGAgent -Force
} catch {}

try {
    if (-not $NoGPG) {
        $Opts = New-ScheduledJobOption -MultipleInstancePolicy StopExisting
        Register-ScheduledJob `
            -Name GPGAgent `
            -Trigger (New-JobTrigger -AtLogOn) `
            -ScheduledJobOption  $Opts `
            -RunNow `
            -ScriptBlock {
                & "${env:ProgramFiles(x86)}/GnuPG/bin/gpg-connect-agent.exe" /bye
            }
        Set-ScheduledTask -TaskName GPGAgent -TaskPath Microsoft\Windows\PowerShell\ScheduledJobs -Principal (New-ScheduledTaskPrincipal -Logontype Interactive -Userid $env:USERNAME)
    }
} catch {
    Write-Output $_
}

# Add startup task to update the kernel in Windows
try {
    Unregister-ScheduledJob -Name UpdateWSL2CustomKernel -Force
} catch {}

try {
    if (-not $NoKernel) {
        $Opts = New-ScheduledJobOption -RequireNetwork -MultipleInstancePolicy StopExisting
        Register-ScheduledJob `
            -Name UpdateWSL2CustomKernel `
            -Trigger (New-JobTrigger -AtLogOn) `
            -ScheduledJobOption $Opts `
            -RunNow `
            -ScriptBlock {
                function Get-IniContent($FilePath)
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

                $latest = (Invoke-RestMethod -Uri 'https://api.github.com/repos/diddlesnaps/WSL2-Linux-Kernel/releases' -UseBasicParsing)[0]
                $latest_version = [version]$latest.tag_name.Replace('linux-msft-snapd-', '').Replace('linux-microsoft-snapd-', '')
                $current_version = [version](Get-Content "$env:APPDATA/wsl2-custom-kernel-version.txt" -ErrorAction SilentlyContinue)
                if (-not $current_version -or $latest_version -gt $current_version) {
                    $assets = $latest.assets | Where-Object {$_.name -Like '*-x86_64'}
                    Invoke-WebRequest -Uri $assets.browser_download_url -OutFile "$env:APPDATA/wsl2-custom-kernel"
                    if ($?) {
                        Move-Item "$env:APPDATA/wsl2-custom-kernel.tmp" "$env:APPDATA/wsl2-custom-kernel.tmp" -Force
                        $latest_version | Set-Content "$env:APPDATA/wsl2-custom-kernel-version.txt"
                        $wslconfig = @{'wsl2'=@{'kernel'=''}}
                        if (Test-Path -Path "$env:USERPROFILE/.wslconfig") {
                            $wslconfig = Get-IniContent "$env:USERPROFILE/.wslconfig"
                        }
                        $wslconfig["wsl2"]["kernel"] = "$env:APPDATA\wsl2-custom-kernel".Replace('\', '\\')
                        Out-IniFile $wslconfig "$env:USERPROFILE/.wslconfig"
                    }
                }
            }
            Set-ScheduledTask -TaskName UpdateWSL2CustomKernel -TaskPath Microsoft\Windows\PowerShell\ScheduledJobs -Principal (New-ScheduledTaskPrincipal -Logontype Interactive -Userid $env:USERNAME)
    }
} catch {
    Write-Output $_
}

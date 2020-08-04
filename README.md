To install:

1. Download the `install.ps1` script
1. Open a PowerShell or CMD window: press `Win + x` then choose either "Command Prompt" or "Windows PowerShell" depending on which your system presents in the menu
1. Run the following command in the PowerShell or CMD window to set up your default distro
    ```powershell
    powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File \path\to\install.ps1
    ```

You can also specify a distro name with the `-distro Ubuntu-20.04` flag:

```powershell
powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File \path\to\install.ps1 -distro Ubuntu-20.04
```

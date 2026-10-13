param([switch]$Disable)
$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$launcher = Join-Path $package 'PersonalAssistant-Computer.exe'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$subKey = $sid + '\Software\Microsoft\Windows\CurrentVersion\Run'
$usersHive = [uint32]2147483651
# The registry provider runs outside an MSIX caller's private registry view.
# Verify the actual per-user startup entry that Windows reads at sign-in.
function Set-StartupValue([string]$valueName, [string]$value) {
    $arguments = @{hDefKey=$usersHive; sSubKeyName=$subKey; sValueName=$valueName; sValue=$value}
    $result = Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName SetStringValue -Arguments $arguments
    if ($result.ReturnValue -ne 0) { throw ('Windows could not save startup: ' + $valueName) }
    $arguments.Remove('sValue')
    $saved = Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName GetStringValue -Arguments $arguments
    if ($saved.ReturnValue -ne 0 -or $saved.sValue -ne $value) { throw ('Windows startup verification failed: ' + $valueName) }
}
$name = 'PersonalAssistantComputer'
if ($Disable) {
    foreach ($valueName in @($name, 'PersonalAssistantCompute')) {
        $result = Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName DeleteValue -Arguments @{hDefKey=$usersHive; sSubKeyName=$subKey; sValueName=$valueName}
        if ($result.ReturnValue -notin @(0, 2)) { throw ('Windows could not remove startup: ' + $valueName) }
    }
    Write-Output 'Automatic companion startup is off.'
    exit
}
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Run this helper from the packaged computer companion.' }
$command = '"' + $launcher + '" --check'
$created = Invoke-CimMethod -Namespace root/default -ClassName StdRegProv -MethodName CreateKey -Arguments @{hDefKey=$usersHive; sSubKeyName=$subKey}
if ($created.ReturnValue -ne 0) { throw 'Windows could not open the startup key.' }
Set-StartupValue $name $command
$dockerCLI = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
if (Test-Path -LiteralPath $dockerCLI) {
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $computeCommand = '"' + $powershell + '" -NoProfile -NonInteractive -WindowStyle Hidden -Command "& ''' + $dockerCLI + ''' desktop start --detach"'
    Set-StartupValue 'PersonalAssistantCompute' $computeCommand
}
Write-Output 'The companion starts silently when you sign in to Windows. Chrome does not need to stay open.'

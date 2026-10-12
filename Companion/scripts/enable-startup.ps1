param([switch]$Disable)
$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$launcher = Join-Path $package 'PersonalAssistant-Computer.exe'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$name = 'PersonalAssistantComputer'
if ($Disable) {
    Remove-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath $key -Name 'PersonalAssistantCompute' -ErrorAction SilentlyContinue
    Write-Output 'Automatic companion startup is off.'
    exit
}
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Run this helper from the packaged computer companion.' }
$command = '"' + $launcher + '" --check'
New-Item -Path $key -Force | Out-Null
New-ItemProperty -LiteralPath $key -Name $name -Value $command -PropertyType String -Force | Out-Null
if ((Get-ItemPropertyValue -LiteralPath $key -Name $name) -ne $command) { throw 'Windows did not save the startup entry.' }
$dockerCLI = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
if (Test-Path -LiteralPath $dockerCLI) {
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $computeCommand = '"' + $powershell + '" -NoProfile -NonInteractive -WindowStyle Hidden -Command "& ''' + $dockerCLI + ''' desktop start --detach"'
    New-ItemProperty -LiteralPath $key -Name 'PersonalAssistantCompute' -Value $computeCommand -PropertyType String -Force | Out-Null
    if ((Get-ItemPropertyValue -LiteralPath $key -Name 'PersonalAssistantCompute') -ne $computeCommand) { throw 'Windows did not save computation startup.' }
}
Write-Output 'The companion starts silently when you sign in to Windows. Chrome does not need to stay open.'

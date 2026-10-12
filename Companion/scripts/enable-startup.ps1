param([switch]$Disable)
$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$launcher = Join-Path $package 'PersonalAssistant-Computer.exe'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$name = 'PersonalAssistantComputer'
if ($Disable) {
    Remove-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue
    Write-Output 'Automatic companion startup is off.'
    exit
}
if (-not (Test-Path -LiteralPath $launcher)) { throw 'Run this helper from the packaged computer companion.' }
$command = '"' + $launcher + '" --check'
New-Item -Path $key -Force | Out-Null
New-ItemProperty -LiteralPath $key -Name $name -Value $command -PropertyType String -Force | Out-Null
if ((Get-ItemPropertyValue -LiteralPath $key -Name $name) -ne $command) { throw 'Windows did not save the startup entry.' }
Write-Output 'The companion starts silently when you sign in to Windows. Chrome does not need to stay open.'

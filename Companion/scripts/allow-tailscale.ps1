$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$node = Join-Path $package 'Runtime\node.exe'
if (-not (Test-Path -LiteralPath $node)) { throw 'Run this from the packaged companion folder.' }
$adapter = Get-NetAdapter -Name 'Tailscale' -ErrorAction Stop
$name = 'PersonalAssistant-Tailscale'
$existing = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
if ($existing) {
    # Preserve the existing address, interface and port restrictions on upgrade.
    Set-NetFirewallRule -Name $name -Program $node | Out-Null
} else {
    New-NetFirewallRule -Name $name -DisplayName 'Personal Assistant (private Tailscale connection)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 48681 -Program $node -Profile Any -InterfaceAlias $adapter.Name -RemoteAddress '100.64.0.0/10' | Out-Null
}
Write-Output 'The paired companion endpoint is reachable through the Tailscale interface. Setup remains local to this PC.'

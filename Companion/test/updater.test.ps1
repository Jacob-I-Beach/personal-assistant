$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixture = Join-Path $repo ('.build\updater-' + [Guid]::NewGuid().ToString('N'))
$old = Join-Path $fixture 'previous'
$new = Join-Path $fixture 'new'
foreach ($root in @($old,$new)) {
    New-Item -ItemType Directory -Path (Join-Path $root 'Runtime'),(Join-Path $root 'src'),(Join-Path $root 'scripts') -Force | Out-Null
    '{"name":"personal-assistant-companion","version":"1.1.0"}' | Set-Content -LiteralPath (Join-Path $root 'package.json')
    'fixture - never execute' | Set-Content -LiteralPath (Join-Path $root 'PersonalAssistant-Computer.exe')
    'identical runtime fixture - never execute' | Set-Content -LiteralPath (Join-Path $root 'Runtime\node.exe')
    'fixture' | Set-Content -LiteralPath (Join-Path $root 'src\server.mjs')
}
Copy-Item -LiteralPath (Join-Path $repo 'Companion\scripts\install-update.ps1'),(Join-Path $repo 'Companion\scripts\update-support.ps1') -Destination (Join-Path $new 'scripts')
$global:updaterTestMode = 'missing-startup'
$global:updaterTestRuntime = Join-Path $old 'Runtime\node.exe'
$global:updaterTestChecks = 0

# Exercise the real updater under Windows PowerShell 5.1 without launching a
# service, changing startup/firewall, or touching the real account/data store.
function Start-Process { throw 'A read-only updater check attempted to start a process.' }
function Get-ItemProperty {
    [CmdletBinding()] param($LiteralPath)
    if ($global:updaterTestMode -eq 'stale-startup') { return [pscustomobject]@{PersonalAssistantComputer='"C:\missing\PersonalAssistant-Computer.exe" --check'} }
    return [pscustomobject]@{}
}
function Get-NetFirewallRule {
    [CmdletBinding()] param($Name)
    if ($global:updaterTestMode -eq 'no-registration') { throw 'No rule' }
    return [pscustomobject]@{Name=$Name}
}
function Get-NetFirewallApplicationFilter {
    [CmdletBinding()] param([Parameter(ValueFromPipeline=$true)]$InputObject)
    process { [pscustomobject]@{Program=$global:updaterTestRuntime} }
}
function Get-NetTCPConnection {
    [CmdletBinding()] param($LocalPort,$State)
    if ($global:updaterTestMode -in @('occupied-port','busy','idle')) { [pscustomobject]@{OwningProcess=12345} }
}
function Get-Process {
    [CmdletBinding()] param($Id)
    [pscustomobject]@{Path=$global:updaterTestRuntime}
}
function Invoke-WebRequest {
    [CmdletBinding()] param($Uri,[switch]$UseBasicParsing,$SessionVariable,$TimeoutSec)
    if ($global:updaterTestMode -notin @('busy','idle')) { throw 'Fixture: stopped service' }
    Set-Variable -Name $SessionVariable -Value 'fixture-session' -Scope 1
    [pscustomobject]@{Content='<meta name="csrf-token" content="fixture">'}
}
function Invoke-RestMethod {
    [CmdletBinding()] param($Method,$Uri,$WebSession,$Headers,$ContentType,$Body,$TimeoutSec)
    if (-not $Uri.EndsWith('/api/status')) { throw 'Unexpected mutation request' }
    $jobs = @()
    if ($global:updaterTestMode -eq 'busy') { $jobs = @([pscustomobject]@{status='running'}) }
    [pscustomobject]@{version='1.0.3';package_path=$old;jobs=$jobs}
}
function Assert-Check($mode,$pattern) {
    $global:updaterTestMode = $mode
    $output = (& (Join-Path $new 'scripts\install-update.ps1') -CheckOnly) -join "`n"
    if ($output -notmatch $pattern) { throw ('Unexpected result for ' + $mode + ': ' + $output) }
    if (Test-Path -LiteralPath (Join-Path $new 'Runtime\authorized-node.txt')) { throw 'CheckOnly changed the runtime.' }
    $global:updaterTestChecks++
}
Assert-Check 'missing-startup' 'service stopped; reuse existing firewall permission: True'
Assert-Check 'no-registration' 'service stopped; reuse existing firewall permission: False'
Assert-Check 'stale-startup' 'service stopped; reuse existing firewall permission: True'
Assert-Check 'idle' 'service running 1.0.3; reuse existing firewall permission: True'
foreach ($case in @(@('occupied-port','using the companion ports'),@('busy','task is still active'))) {
    $global:updaterTestMode = $case[0]
    $caught = $false
    try { & (Join-Path $new 'scripts\install-update.ps1') -CheckOnly | Out-Null }
    catch { if ($_.Exception.Message -notmatch $case[1]) { throw }; $caught=$true }
    if (-not $caught) { throw ('Expected refusal for ' + $case[0]) }
    $global:updaterTestChecks++
}
'different fixture runtime' | Set-Content -LiteralPath (Join-Path $new 'Runtime\node.exe')
Assert-Check 'missing-startup' 'reuse existing firewall permission: False'
Write-Output ($global:updaterTestChecks.ToString() + ' updater regression checks passed; no service or machine settings changed.')


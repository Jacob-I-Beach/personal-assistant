param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$launcher = Join-Path $package 'PersonalAssistant-Computer.exe'
$node = Join-Path $package 'Runtime\node.exe'
$origin = 'http://127.0.0.1:48680'
if (-not (Test-Path -LiteralPath $launcher) -or -not (Test-Path -LiteralPath $node)) { throw 'Keep the complete companion package together.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal] $identity
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Open this update normally. It requests administrator rights only for the firewall; the companion should run as your normal user.' }

function Read-Setup {
    $page = Invoke-WebRequest -Uri ($origin + '/') -UseBasicParsing -SessionVariable session -TimeoutSec 5
    if ($page.Content -notmatch '<meta name="csrf-token" content="([^"]+)">') { throw 'The running service is not the Personal Assistant setup.' }
    return @{Session=$session; Headers=@{Origin=$origin; 'x-assistant-csrf'=$Matches[1]}}
}
function Setup-Request($connection, $path) {
    Invoke-RestMethod -Method Post -Uri ($origin + $path) -WebSession $connection.Session -Headers $connection.Headers -ContentType 'application/json' -Body '{}' -TimeoutSec 10
}
function Launch-Companion($path) {
    $process = Start-Process -FilePath $path -ArgumentList '--check' -WindowStyle Hidden -PassThru
    # Do not use Start-Process -Wait: it also waits for the long-lived child server.
    if (-not $process.WaitForExit(25000) -or $process.ExitCode -ne 0) { throw 'The companion did not become ready. The old package and all saved data are preserved.' }
}

$connection = Read-Setup
$status = Setup-Request $connection '/api/status'
$active = @($status.jobs | Where-Object { $_.status -notin @('completed','failed','cancelled','interrupted') })
if ($active.Count -gt 0) { throw 'A computer task is still active. Let it finish, then open this update again.' }
$version = (Get-Content -LiteralPath (Join-Path $package 'package.json') -Raw | ConvertFrom-Json).version
if ($CheckOnly) {
    Write-Output ('Ready to update the idle companion from ' + $status.version + ' to ' + $version + '. Pairing, account and saved tasks stay in their existing data folder.')
    exit
}

$ownerPID = (Get-NetTCPConnection -LocalPort 48681 -State Listen | Select-Object -First 1).OwningProcess
$oldNode = (Get-Process -Id $ownerPID).Path
$oldPackage = Split-Path -Parent (Split-Path -Parent $oldNode)
$previousLauncher = Join-Path $oldPackage 'PersonalAssistant-Computer.exe'
if (-not (Test-Path -LiteralPath $previousLauncher)) { throw 'The running companion location could not be verified. Keep it running and use its setup controls to update.' }

$stopped = $false
try {
    Setup-Request $connection '/api/quit' | Out-Null
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if (-not (Get-NetTCPConnection -LocalPort 48681 -State Listen -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 250
    }
    if (Get-NetTCPConnection -LocalPort 48681 -State Listen -ErrorAction SilentlyContinue) { throw 'The existing companion is still closing. Its work was not force-stopped.' }
    $stopped = $true
    Write-Output 'Approve the Windows prompt to update the existing Tailscale firewall rule.'
    $helper = Join-Path $PSScriptRoot 'allow-tailscale.ps1'
    $administrator = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-File',('"' + $helper + '"')) -PassThru
    $administrator.WaitForExit()
    if ($administrator.ExitCode -ne 0) { throw 'Windows did not apply the firewall update.' }
    Launch-Companion $launcher
    $verified = Setup-Request (Read-Setup) '/api/status'
    if ($verified.version -ne $version) { throw 'A different companion version answered. The update has not been confirmed.' }
    & (Join-Path $PSScriptRoot 'enable-startup.ps1')
    Write-Output ('Personal Assistant Computer ' + $version + ' is running. The existing iPhone pairing is retained; another code scan is not needed.')
} catch {
    if ($stopped -and -not (Get-NetTCPConnection -LocalPort 48681 -State Listen -ErrorAction SilentlyContinue)) {
        try { Launch-Companion $previousLauncher } catch { Write-Warning 'Open the previous companion to restore service.' }
    }
    throw
}

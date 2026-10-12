param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$launcher = Join-Path $package 'PersonalAssistant-Computer.exe'
$node = Join-Path $package 'Runtime\node.exe'
$origin = 'http://127.0.0.1:48680'
. (Join-Path $PSScriptRoot 'update-support.ps1')
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
function Companion-Listeners {
    @(Get-NetTCPConnection -LocalPort 48680,48681 -State Listen -ErrorAction SilentlyContinue)
}

$connection = $null
try { $connection = Read-Setup } catch {
    if (@(Companion-Listeners).Count -gt 0) { throw 'A service is using the companion ports but its setup is not ready. Wait for it to finish starting, then retry. No service was stopped.' }
}
$status = $null
if ($connection) {
    $status = Setup-Request $connection '/api/status'
    $active = @($status.jobs | Where-Object { $_.status -notin @('completed','failed','cancelled','interrupted') })
    if ($active.Count -gt 0) { throw 'A computer task is still active. Let it finish, then open this update again.' }
}
$version = (Get-Content -LiteralPath (Join-Path $package 'package.json') -Raw | ConvertFrom-Json).version
$registered = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).PersonalAssistantComputer
$allowedProgram = $null
try {
    $rule = Get-NetFirewallRule -Name 'PersonalAssistant-Tailscale' -ErrorAction Stop
    $allowedProgram = ($rule | Get-NetFirewallApplicationFilter -ErrorAction Stop).Program
} catch { Write-Output 'The existing firewall permission could not be read. Windows may request approval to configure the private connection.' }
$previous = Get-CompanionInstallation -StartupCommand $registered -FirewallProgram $allowedProgram
$previousLauncher = $null
$oldNode = $null
if ($previous) {
    $previousLauncher = $previous.Launcher
    $oldNode = $previous.Runtime
}
if ($connection) {
    $ownerPID = (Get-NetTCPConnection -LocalPort 48681 -State Listen | Select-Object -First 1).OwningProcess
    $oldNode = (Get-Process -Id $ownerPID).Path
    $oldPackage = Split-Path -Parent (Split-Path -Parent $oldNode)
    if ($status.package_path -and [IO.Path]::IsPathRooted($status.package_path)) { $oldPackage = [IO.Path]::GetFullPath($status.package_path) }
    $previousLauncher = Join-Path $oldPackage 'PersonalAssistant-Computer.exe'
    if (-not (Test-Path -LiteralPath $previousLauncher -PathType Leaf)) { throw 'The running companion location could not be verified. No service was stopped.' }
}
$reuseRuntime = Test-CompanionRuntimeReuse -ExistingRuntime $oldNode -PackagedRuntime $node -FirewallProgram $allowedProgram
if ($CheckOnly) {
    $serviceState = 'stopped'
    if ($status) { $serviceState = 'running ' + $status.version }
    Write-Output ('Ready to update to ' + $version + '; service ' + $serviceState + '; reuse existing firewall permission: ' + $reuseRuntime + '. Account, pairing and saved tasks stay in their existing data folder.')
    return
}

# A second launcher may have started after discovery. Check for active work
# on a fresh invocation instead of replacing an uninspected service.
if (-not $connection -and @(Companion-Listeners).Count -gt 0) { throw 'The companion started while preparing the update. Run the updater again so it can check for active work.' }
if ($reuseRuntime) {
    # Reuse only a byte-identical runtime with the existing firewall permission.
    [IO.File]::WriteAllText((Join-Path $package 'Runtime\authorized-node.txt'), $oldNode)
} else {
    $runtimeOverride = Join-Path $package 'Runtime\authorized-node.txt'
    if (Test-Path -LiteralPath $runtimeOverride) { Remove-Item -LiteralPath $runtimeOverride }
}

$stopped = -not $connection
try {
    if ($connection) {
        Setup-Request $connection '/api/quit' | Out-Null
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            if (@(Companion-Listeners).Count -eq 0) { break }
            Start-Sleep -Milliseconds 250
        }
        if (@(Companion-Listeners).Count -gt 0) { throw 'The existing companion is still closing. Its work was not force-stopped.' }
        $stopped = $true
    }
    if (-not $reuseRuntime) {
        Write-Output 'Approve the Windows prompt to update the existing Tailscale firewall rule.'
        $helper = Join-Path $PSScriptRoot 'allow-tailscale.ps1'
        $administrator = Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-File',('"' + $helper + '"')) -PassThru
        $administrator.WaitForExit()
        if ($administrator.ExitCode -ne 0) { throw 'Windows did not apply the firewall update.' }
    }
    Launch-Companion $launcher
    $verified = Setup-Request (Read-Setup) '/api/status'
    if ($verified.version -ne $version) { throw 'A different companion version answered. The update has not been confirmed.' }
    if ($status -and @($verified.devices).Count -lt @($status.devices).Count) { throw 'The new service sees fewer paired devices than before the update. Keep both data stores and inspect the saved report before pairing again.' }
    & (Join-Path $PSScriptRoot 'enable-startup.ps1')
    Write-Output ('Personal Assistant Computer ' + $version + ' is running. ChatGPT: ' + $verified.session.status + '; paired devices: ' + @($verified.devices).Count + '.')
    if ($verified.data_path) { Write-Output ('Saved data: ' + $verified.data_path) }
} catch {
    if ($stopped -and $previousLauncher -and @(Companion-Listeners).Count -eq 0) {
        try { Launch-Companion $previousLauncher } catch { Write-Warning 'Open the previous companion to restore service.' }
    }
    throw
}

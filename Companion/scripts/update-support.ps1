# Startup registration is optional. Discovery never launches or modifies anything.
function Get-CompanionInstallation {
    param([string]$StartupCommand, [string]$FirewallProgram)
    $candidates = @()
    if ($StartupCommand -match '^\s*"([^"\r\n]+PersonalAssistant-Computer\.exe)"\s+--check\s*$') {
        if ([IO.Path]::IsPathRooted($Matches[1])) { $candidates += Split-Path -Parent $Matches[1] }
    }
    if ($FirewallProgram -and [IO.Path]::IsPathRooted($FirewallProgram) -and
        (Split-Path -Leaf $FirewallProgram) -eq 'node.exe' -and
        (Split-Path -Leaf (Split-Path -Parent $FirewallProgram)) -eq 'Runtime') {
        $candidates += Split-Path -Parent (Split-Path -Parent $FirewallProgram)
    }
    foreach ($candidate in $candidates | Select-Object -Unique) {
        try {
            $root = [IO.Path]::GetFullPath($candidate)
            $manifest = Get-Content -LiteralPath (Join-Path $root 'package.json') -Raw -ErrorAction Stop | ConvertFrom-Json
            $launcher = Join-Path $root 'PersonalAssistant-Computer.exe'
            $runtime = Join-Path $root 'Runtime\node.exe'
            if ($manifest.name -eq 'personal-assistant-companion' -and
                (Test-Path -LiteralPath $launcher -PathType Leaf) -and
                (Test-Path -LiteralPath $runtime -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $root 'src\server.mjs') -PathType Leaf)) {
                return @{Package=$root; Launcher=$launcher; Runtime=$runtime; Version=$manifest.version}
            }
        } catch { continue }
    }
    return $null
}

function Test-CompanionRuntimeReuse {
    param([string]$ExistingRuntime, [string]$PackagedRuntime, [string]$FirewallProgram)
    if (-not $ExistingRuntime -or -not $FirewallProgram) { return $false }
    try {
        return [IO.Path]::GetFullPath($ExistingRuntime) -eq [IO.Path]::GetFullPath($FirewallProgram) -and
            (Get-FileHash -LiteralPath $ExistingRuntime -Algorithm SHA256).Hash -eq
            (Get-FileHash -LiteralPath $PackagedRuntime -Algorithm SHA256).Hash
    } catch { return $false }
}

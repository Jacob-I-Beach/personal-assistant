param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'Companion'
$target = [IO.Path]::GetFullPath($OutputDirectory)
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '..\PersonalAssistant-Computer'))
if (-not $target.StartsWith($allowedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'The package destination must be inside outputs\PersonalAssistant-Computer.' }
if (Test-Path -LiteralPath $target) { throw 'Choose a new package directory; existing packages are preserved.' }
New-Item -ItemType Directory -Path $target -Force | Out-Null
foreach ($entry in @('src','ui','scripts','skills','compute','vendor','package.json','package-lock.json','README.md','PROTOCOL.md','Update-Companion.cmd')) {
    Copy-Item -LiteralPath (Join-Path $source $entry) -Destination $target -Recurse
}
New-Item -ItemType Directory -Path (Join-Path $target 'Runtime') | Out-Null
$nodePath = (Get-Command node.exe).Source
Copy-Item -LiteralPath $nodePath -Destination (Join-Path $target 'Runtime\node.exe')
Push-Location $target
try { & npm.cmd ci --omit=dev --ignore-scripts; if ($LASTEXITCODE -ne 0) { throw 'Production dependencies did not install.' } }
finally { Pop-Location }
$sdkLink = Join-Path $target 'node_modules\@siwc\local'
$sdkSource = [IO.Path]::GetFullPath((Join-Path $target 'vendor\siwc-local'))
$sdkEntry = Get-Item -LiteralPath $sdkLink
if ($sdkEntry.LinkType -eq 'Junction') {
    if ([IO.Path]::GetFullPath([string]$sdkEntry.Target) -ne $sdkSource -or -not $sdkSource.StartsWith($target + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected local SDK link target.' }
    # Remove this package's junction only, preserving its verified source.
    [IO.Directory]::Delete($sdkLink)
    Copy-Item -LiteralPath $sdkSource -Destination $sdkLink -Recurse
}
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe /optimize+ /reference:System.Windows.Forms.dll (('/out:' + (Join-Path $target 'PersonalAssistant-Computer.exe'))) (Join-Path $source 'Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw 'The Windows launcher did not compile.' }
$desktopReferences = @('/reference:System.Drawing.dll','/reference:System.Windows.Forms.dll','/reference:System.Web.Extensions.dll')
$frameworkReferences = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\WPF'
foreach ($assembly in @('UIAutomationClient.dll','UIAutomationTypes.dll','WindowsBase.dll')) { $desktopReferences += '/reference:' + (Join-Path $frameworkReferences $assembly) }
& $compiler /nologo /target:exe /optimize+ @desktopReferences (('/out:' + (Join-Path $target 'Runtime\AssistantDesktop.exe'))) (Join-Path $source 'AssistantDesktop.cs')
if ($LASTEXITCODE -ne 0) { throw 'The Windows desktop tool did not compile.' }
$files = Get-ChildItem -LiteralPath $target -Recurse -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' }
$lines = $files | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.FullName.Substring($target.Length + 1).Replace('\','/') }
$lines | Set-Content -LiteralPath (Join-Path $target 'SHA256SUMS.txt') -Encoding utf8
Write-Output "Companion package: $target"

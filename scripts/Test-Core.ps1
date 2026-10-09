param([switch]$Integration)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalPath = $env:Path
$originalSDK = $env:SDKROOT
$originalFixture = $env:ASSISTANT_FIXTURE_BASE_URL
$fixtureProcess = $null
$testExitCode = 1
Push-Location -LiteralPath $projectRoot
try {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $userSDK = [Environment]::GetEnvironmentVariable('SDKROOT', 'User')
    if ($userSDK) { $env:SDKROOT = $userSDK }
    $swiftCommand = Get-Command swift -ErrorAction SilentlyContinue
    if (-not $swiftCommand) { throw 'Install the official Swift Windows toolchain, then retry. See README.md.' }
    if ($Integration) {
        $pythonCommand = Get-Command python -ErrorAction Stop
        $buildDirectory = Join-Path $projectRoot '.build'
        New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
        $portFile = Join-Path $buildDirectory ('fixture-port-' + [guid]::NewGuid().ToString() + '.txt')
        $fixtureScript = Join-Path $PSScriptRoot 'mock_model_server.py'
        $fixtureProcess = Start-Process -FilePath $pythonCommand.Source -ArgumentList @("`"$fixtureScript`"", '--port-file', "`"$portFile`"") -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
        $deadline = (Get-Date).AddSeconds(10)
        while (-not (Test-Path -LiteralPath $portFile)) {
            if ($fixtureProcess.HasExited) { throw 'The local test server exited before startup.' }
            if ((Get-Date) -gt $deadline) { throw 'The local test server did not start in time.' }
            Start-Sleep -Milliseconds 100
        }
        $fixturePort = (Get-Content -LiteralPath $portFile -Raw).Trim()
        $env:ASSISTANT_FIXTURE_BASE_URL = 'http://127.0.0.1:' + $fixturePort
    }
    & $swiftCommand.Source test
    $testExitCode = $LASTEXITCODE
} finally {
    if ($fixtureProcess -and -not $fixtureProcess.HasExited) { Stop-Process -InputObject $fixtureProcess -ErrorAction SilentlyContinue }
    $env:Path = $originalPath
    $env:SDKROOT = $originalSDK
    $env:ASSISTANT_FIXTURE_BASE_URL = $originalFixture
    Pop-Location
}
exit $testExitCode

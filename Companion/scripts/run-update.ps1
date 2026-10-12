$ErrorActionPreference = 'Stop'
$logDirectory = Join-Path $env:LOCALAPPDATA 'PersonalAssistantCompanion\logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$log = Join-Path $logDirectory 'update.log'
Start-Transcript -LiteralPath $log -Append | Out-Null
$result = 0
try {
    & (Join-Path $PSScriptRoot 'install-update.ps1')
} catch {
    Write-Host ('Update could not finish: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('The update report is saved at ' + $log)
    $result = 1
} finally { Stop-Transcript | Out-Null }
exit $result

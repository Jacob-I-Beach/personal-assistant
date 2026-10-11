# Run by the user as administrator only when private Wi-Fi pairing is blocked.
$companionRoot = Split-Path -Parent $PSScriptRoot
$companionNode = Join-Path $companionRoot 'Runtime\node.exe'
if (-not (Test-Path -LiteralPath $companionNode -PathType Leaf)) { throw 'Keep this helper in the complete companion package.' }
$companionRule = 'PersonalAssistant-Computer-PrivateWiFi'
$existingRule = Get-NetFirewallRule -Name $companionRule -ErrorAction SilentlyContinue
if ($existingRule) { Write-Output 'The private Wi-Fi rule already exists.'; exit }
New-NetFirewallRule -Name $companionRule -DisplayName 'Personal Assistant Computer (private Wi-Fi)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 48681 -Program $companionNode -Profile Private -RemoteAddress LocalSubnet | Out-Null
Write-Output 'Private local-network access is enabled for the paired companion endpoint. Public networks and other ports are unchanged.'

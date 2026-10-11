param([Parameter(Mandatory=$true)][ValidateSet('protect','unprotect')][string]$Operation)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$taskInput = [Convert]::FromBase64String([Console]::In.ReadToEnd())
$taskEntropy = [Text.Encoding]::UTF8.GetBytes('PersonalAssistant.Companion.ProtectedData.v1')
try {
    if ($Operation -eq 'protect') {
        $taskResult = [Security.Cryptography.ProtectedData]::Protect($taskInput, $taskEntropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    } else {
        $taskResult = [Security.Cryptography.ProtectedData]::Unprotect($taskInput, $taskEntropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    }
    [Console]::Out.Write([Convert]::ToBase64String($taskResult))
} finally {
    [Array]::Clear($taskInput, 0, $taskInput.Length)
}

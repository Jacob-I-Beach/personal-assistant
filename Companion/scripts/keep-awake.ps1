Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AssistantPowerLease {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern uint SetThreadExecutionState(uint flags);
}
'@
try {
    [void][AssistantPowerLease]::SetThreadExecutionState([uint32]2147483649)
    # The parent owns this pipe. Closing the companion releases the lease;
    # display sleep and the user's permanent power settings are unchanged.
    while ($null -ne [Console]::ReadLine()) { }
} finally {
    [void][AssistantPowerLease]::SetThreadExecutionState([uint32]2147483648)
}

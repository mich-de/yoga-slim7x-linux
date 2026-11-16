param($log, [long]$len = 3539886080, [int]$num = 1)
$ErrorActionPreference = 'Stop'
function L($m) { "$(Get-Date -f HH:mm:ss) $m" | Out-File $log -Append -Encoding utf8 }
try {
    $d = Get-Disk -Number $num
    if ($d.FriendlyName -notlike '*TS256GSS*' -or $d.BusType -ne 'USB') { throw "disco $num inatteso: $($d.FriendlyName)" }
    Add-Type -Namespace W -Name K -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string n, uint a, uint s, System.IntPtr sec, uint c, uint f, System.IntPtr t);
'@
    $h = [W.K]::CreateFile("\\.\PhysicalDrive$num", [uint32]2147483648, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)  # GENERIC_READ
    if ($h.IsInvalid) { throw "CreateFile errore $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    $fs = New-Object IO.FileStream($h, [IO.FileAccess]::Read, 1)
    $sha = [Security.Cryptography.SHA256]::Create(); $buf = New-Object byte[] (4MB); [long]$rem = $len
    while ($rem -gt 0) {
        [int]$want = if ($rem -lt $buf.Length) { [int]$rem } else { $buf.Length }
        $n = $fs.Read($buf, 0, $want); if ($n -le 0) { throw "lettura corta, mancano $rem byte" }
        $null = $sha.TransformBlock($buf, 0, $n, $null, 0); $rem -= $n
    }
    $null = $sha.TransformFinalBlock($buf, 0, 0); $fs.Close()
    L ("sha256 disco: " + (($sha.Hash | % { $_.ToString('x2') }) -join ''))
} catch { L "ERRORE: $_" }

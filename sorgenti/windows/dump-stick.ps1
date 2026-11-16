param($out, $log)
# SOLA LETTURA sulla chiavetta: copia i primi 7,8 GB (ISO + ESP + STRUMENTI) in un file immagine per la prova in macchina virtuale.
$ErrorActionPreference = 'Stop'
function L($m) { "$(Get-Date -f HH:mm:ss) $m" | Out-File $log -Append -Encoding utf8 }
try {
    $d = Get-Disk -Number 1
    if ($d.FriendlyName -notlike '*TS256GSS*') { throw "disco 1 inatteso: $($d.FriendlyName)" }
    $p3 = Get-Partition -DiskNumber 1 -PartitionNumber 3
    [long]$len = $p3.Offset + $p3.Size
    New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
    Add-Type -Namespace Dump -Name K -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string n, uint a, uint s, System.IntPtr sec, uint c, uint f, System.IntPtr t);
'@
    $h = [Dump.K]::CreateFile('\\.\PhysicalDrive1', [uint32]2147483648, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h.IsInvalid) { throw 'apertura disco fallita' }
    $in = New-Object IO.FileStream($h, [IO.FileAccess]::Read, 1)
    $o = [IO.File]::Create($out)
    $buf = New-Object byte[] (8MB); [long]$rem = $len
    while ($rem -gt 0) {
        $n = $in.Read($buf, 0, $buf.Length); if ($n -le 0) { throw 'lettura interrotta' }
        [int]$use = if ($rem -lt $n) { [int]$rem } else { $n }
        $o.Write($buf, 0, $use); $rem -= $use
    }
    $o.Close(); $in.Close()
    L "immagine scritta: $out ($len byte)"
} catch { L "ERRORE: $_" }

param($iso, $log, [int]$num = 1)
$ErrorActionPreference = 'Stop'
function L($m) { "$(Get-Date -f HH:mm:ss) $m" | Out-File $log -Append -Encoding utf8 }
try {
    $d = Get-Disk -Number $num
    # guard: deve essere il Transcend USB da 256 GB, mai il disco di sistema
    if ($d.FriendlyName -notlike '*TS256GSS*' -or $d.BusType -ne 'USB' -or $d.Size -ne 256060514304 -or $d.IsBoot -or $d.IsSystem) {
        throw "Disco $num non corrisponde: $($d.FriendlyName) $($d.BusType) $($d.Size) boot=$($d.IsBoot)"
    }
    L "disco ok: $($d.FriendlyName)"
    $dp = Join-Path (Split-Path $log) 'dp.txt'
    "select disk $num`r`nclean`r`nrescan`r`n" | Out-File $dp -Encoding ascii
    $out = diskpart /s $dp | Out-String; L $out.Trim()
    if ((Get-Disk -Number $num).NumberOfPartitions -ne 0) { throw "diskpart clean non ha rimosso le partizioni" }
    L "clean ok"

    Add-Type -Namespace W -Name K -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string n, uint a, uint s, System.IntPtr sec, uint c, uint f, System.IntPtr t);
'@
    $h = [W.K]::CreateFile("\\.\PhysicalDrive$num", [uint32]3221225472, 3, [IntPtr]::Zero, 3, 0x20000000, [IntPtr]::Zero)  # FILE_FLAG_WRITE_THROUGH
    if ($h.IsInvalid) { throw "CreateFile errore $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    $fs = New-Object IO.FileStream($h, [IO.FileAccess]::ReadWrite, 1)
    $in = [IO.File]::OpenRead($iso); $len = $in.Length
    $buf = New-Object byte[] (4MB); $tot = 0; $next = 512MB
    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
        $fs.Write($buf, 0, $n); $tot += $n
        if ($tot -ge $next) { L "scritti $([math]::Round($tot/1MB)) / $([math]::Round($len/1MB)) MB"; $next += 512MB }
    }
    $fs.Flush(); L "scrittura completata: $tot byte"

    $fs.Position = 0; $sha = [Security.Cryptography.SHA256]::Create(); $rem = $len
    while ($rem -gt 0) {
        $n = $fs.Read($buf, 0, [int][math]::Min($buf.Length, $rem)); if ($n -le 0) { throw "lettura corta" }
        $null = $sha.TransformBlock($buf, 0, $n, $null, 0); $rem -= $n
    }
    $null = $sha.TransformFinalBlock($buf, 0, 0)
    L ("verifica sha256: " + (($sha.Hash | % { $_.ToString('x2') }) -join ''))
    $fs.Close(); $in.Close()
    Update-Disk -Number $num
    L "FINE"
} catch { L "ERRORE: $_" }

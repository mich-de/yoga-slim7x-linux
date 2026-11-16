param($out)
# SOLA LETTURA: cerca nei settori grezzi della chiavetta (disco 1) testo di file sovrascritti.
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $out 'scan.log'
function L($m) { "$m" | Out-File $log -Append -Encoding utf8 }
try {
    $d = Get-Disk -Number 1
    if ($d.FriendlyName -notlike '*TS256GSS*') { throw "disco 1 inatteso: $($d.FriendlyName)" }
    Add-Type -Namespace RawScan -Name K -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string n, uint a, uint s, System.IntPtr sec, uint c, uint f, System.IntPtr t);
'@
    $h = [RawScan.K]::CreateFile('\\.\PhysicalDrive1', [uint32]2147483648, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)   # GENERIC_READ
    if ($h.IsInvalid) { throw "apertura disco fallita" }
    $fs = New-Object IO.FileStream($h, [IO.FileAccess]::Read, 1)
    $lat = [Text.Encoding]::GetEncoding(28591)
    $areas = @(@{n = 'esp'; off = [long]3508396032; len = [long]31457280; keys = @('kbd100k', 'FIX TASTIERA', 'devicetree') },
               @{n = 'strumenti'; off = [long]3539992576; len = [long]400MB; keys = @('# HANDOFF', 'STRUMENTI - ', 'FIX TASTIERA', 'i2cslow', 'wsagain') })
    foreach ($a in $areas) {
        $fs.Position = $a.off; $buf = New-Object byte[] (16MB); [long]$done = 0; $hits = @{}
        while ($done -lt $a.len) {
            [int]$want = if (($a.len - $done) -lt $buf.Length) { [int]($a.len - $done) } else { $buf.Length }
            $n = $fs.Read($buf, 0, $want); if ($n -le 0) { break }
            $s = $lat.GetString($buf, 0, $n)
            foreach ($k in $a.keys) {
                $i = 0
                while (($i = $s.IndexOf($k, $i, [StringComparison]::Ordinal)) -ge 0) {
                    $blk = [long][math]::Floor(($done + $i) / 4096)   # finestre da 4 KiB
                    if (-not $hits.ContainsKey($blk)) { $hits[$blk] = $k }
                    $i += $k.Length
                }
            }
            $done += $n
        }
        L "$($a.n): blocchi con corrispondenze: $($hits.Count)"
        # scrive ogni gruppo di blocchi contigui come un file di testo
        $prev = -10; $cur = $null; $idx = 0
        foreach ($blk in ($hits.Keys | Sort-Object)) {
            if ($blk -ne $prev + 1) { $idx++; $cur = Join-Path $out ("{0}-{1:D3}-blk{2}.txt" -f $a.n, $idx, $blk) }
            $fs.Position = $a.off + $blk * 4096; $b = New-Object byte[] 4096; $null = $fs.Read($b, 0, 4096)
            $t = $lat.GetString($b).TrimEnd([char]0)
            [IO.File]::AppendAllText($cur, $t, $lat)
            $prev = $blk
        }
    }
    $fs.Close()
    Get-ChildItem $out -Filter *.txt | ForEach-Object { L ("{0,8}  {1}" -f $_.Length, $_.Name) }
} catch { L "ERRORE: $_" }

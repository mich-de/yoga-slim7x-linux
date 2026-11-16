param($src, $log)
$ErrorActionPreference = 'Stop'
function L($m) { "$(Get-Date -f HH:mm:ss) $m" | Out-File $log -Append -Encoding utf8 }
try {
    $d = Get-Disk -Number 1
    if ($d.FriendlyName -notlike '*TS256GSS*' -or $d.BusType -ne 'USB' -or $d.IsBoot -or $d.IsSystem) { throw "disco 1 inatteso: $($d.FriendlyName)" }
    $p = Get-Partition -DiskNumber 1
    if ($p.Count -ne 2) { throw "attese 2 partizioni (ISO+ESP), trovate $($p.Count)" }
    $dp = Join-Path (Split-Path $log) 'dp5.txt'
    "select disk 1`r`ncreate partition primary size=4096`r`nformat fs=fat32 quick label=STRUMENTI`r`nassign letter=Y`r`n" | Out-File $dp -Encoding ascii
    L ((diskpart /s $dp | Out-String).Trim())
    for ($i = 0; $i -lt 20 -and -not (Test-Path 'Y:\'); $i++) { Start-Sleep -Milliseconds 500 }
    Get-ChildItem $src -File | % { [IO.File]::WriteAllBytes("Y:\$($_.Name)", [IO.File]::ReadAllBytes($_.FullName)); L "copiato $($_.Name) $($_.Length)" }
    L ((Get-Partition -DiskNumber 1 | % { "p$($_.PartitionNumber) off=$($_.Offset) size=$($_.Size) $($_.DriveLetter)" }) -join "; ")
} catch { L "ERRORE: $_" }

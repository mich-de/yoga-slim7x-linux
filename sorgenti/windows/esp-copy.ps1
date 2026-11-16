param($out, $log)
# sola lettura: copia il contenuto della ESP della chiavetta in una cartella per esaminarlo
$ErrorActionPreference = 'Stop'
function L($m) { "$m" | Out-File $log -Append -Encoding utf8 }
$letter = 'X'; $dp = Join-Path (Split-Path $log) 'dp7.txt'
try {
    $d = Get-Disk -Number 1
    if ($d.FriendlyName -notlike '*TS256GSS*') { throw "disco 1 inatteso: $($d.FriendlyName)" }
    "select disk 1`r`nselect partition 2`r`nassign letter=$letter`r`n" | Out-File $dp -Encoding ascii
    $null = diskpart /s $dp
    for ($i = 0; $i -lt 20 -and -not (Test-Path "$($letter):\EFI\BOOT"); $i++) { Start-Sleep -Milliseconds 500 }
    New-Item -ItemType Directory -Force $out | Out-Null
    Get-ChildItem "$($letter):\" -Recurse -File | Sort-Object LastWriteTime | ForEach-Object {
        L ("{0:yyyy-MM-dd HH:mm:ss}  creato {1:HH:mm:ss}  {2,9}  {3}" -f $_.LastWriteTime, $_.CreationTime, $_.Length, $_.FullName.Substring(3))
        if ($_.Length -lt 1MB) { Copy-Item $_.FullName (Join-Path $out ($_.FullName.Substring(3) -replace '\\', '__')) -Force }
    }
} catch { L "ERRORE: $_" }
finally {
    "select disk 1`r`nselect partition 2`r`nremove letter=$letter`r`n" | Out-File $dp -Encoding ascii
    $null = diskpart /s $dp
}

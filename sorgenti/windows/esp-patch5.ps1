param($kit, $log)
# Aggiorna la ESP della chiavetta: prima GUARDA cosa c'e' e verifica che grub.cfg sia l'ultima versione scritta
# da questa sessione (uguale alla copia Y:\boot\grub.cfg); solo allora scrive grub.cfg, strumenti.cpio, HANDOFF.md.
$ErrorActionPreference = 'Stop'
function L($m) { "$m" | Out-File $log -Append -Encoding utf8 }
$letter = 'X'; $dp = Join-Path (Split-Path $log) 'dp9.txt'
try {
    $d = Get-Disk -Number 1
    if ($d.FriendlyName -notlike '*TS256GSS*' -or $d.BusType -ne 'USB' -or $d.IsBoot -or $d.IsSystem) { throw "disco 1 inatteso: $($d.FriendlyName)" }
    $p = Get-Partition -DiskNumber 1 -PartitionNumber 2
    if ($p.Offset -ne 3508396032 -or $p.Size -ne 31457280) { throw "partizione 2 inattesa" }
    "select disk 1`r`nselect partition 2`r`nassign letter=$letter`r`n" | Out-File $dp -Encoding ascii
    $null = diskpart /s $dp
    for ($i = 0; $i -lt 20 -and -not (Test-Path "$($letter):\EFI\BOOT"); $i++) { Start-Sleep -Milliseconds 500 }
    $b = "$($letter):\EFI\BOOT"
    L "PRIMA:"; Get-ChildItem "$($letter):\" -Recurse -File | ForEach-Object { L ("  {0:MM-dd HH:mm:ss} {1,9} {2}" -f $_.LastWriteTime, $_.Length, $_.FullName.Substring(3)) }
    if ((Get-FileHash "$b\grub.cfg").Hash -ne (Get-FileHash 'Y:\boot\grub.cfg').Hash) { throw "grub.cfg sulla ESP e' diverso dall'ultima versione di questa sessione (Y:\boot\grub.cfg): qualcun altro l'ha cambiato, non lo tocco" }
    foreach ($need in 'grub.cfg.orig', 'grub.cfg.bak-1530', 'grub.cfg.bak-1600', 'yoga7x-kbd100k.dtb') { if (-not (Test-Path "$b\$need")) { throw "manca $need sulla ESP" } }
    Copy-Item "$b\grub.cfg" "$b\grub.cfg.bak-1956" -Force
    [IO.File]::WriteAllBytes("$b\grub.cfg", [IO.File]::ReadAllBytes("$kit\boot\grub.cfg"))
    [IO.File]::WriteAllBytes("$($letter):\strumenti.cpio", [IO.File]::ReadAllBytes("$kit\boot\strumenti.cpio"))
    [IO.File]::WriteAllBytes("$($letter):\HANDOFF.md", [IO.File]::ReadAllBytes("$kit\strumenti\HANDOFF.md"))
    $ok1 = (Get-FileHash "$b\grub.cfg").Hash -eq (Get-FileHash "$kit\boot\grub.cfg").Hash
    $ok2 = (Get-FileHash "$($letter):\strumenti.cpio").Hash -eq (Get-FileHash "$kit\boot\strumenti.cpio").Hash
    L "grub.cfg uguale allo staging: $ok1   strumenti.cpio uguale: $ok2"
    L "DOPO:"; Get-ChildItem "$($letter):\" -Recurse -File | ForEach-Object { L ("  {0:MM-dd HH:mm:ss} {1,9} {2}" -f $_.LastWriteTime, $_.Length, $_.FullName.Substring(3)) }
} catch { L "ERRORE: $_" }
finally {
    "select disk 1`r`nselect partition 2`r`nremove letter=$letter`r`n" | Out-File $dp -Encoding ascii
    $null = diskpart /s $dp
}

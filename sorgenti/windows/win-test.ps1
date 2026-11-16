param($log)
# Prova in sola lettura / a vuoto dei tre script Windows del kit (nessuna modifica a dischi o firmware).
$ErrorActionPreference = 'Continue'
function Run($titolo, [scriptblock]$sb) {
    "===== $titolo" | Out-File $log -Append -Encoding utf8
    try { & $sb *>&1 | Out-String | Out-File $log -Append -Encoding utf8 } catch { "ECCEZIONE (attesa se e' un controllo di sicurezza): $_" | Out-File $log -Append -Encoding utf8 }
}
Run 'secureboot-stato.ps1' { & 'Y:\windows\secureboot-stato.ps1' }
Run 'scrivi-iso-su-usb.ps1 (senza -Conferma: prova a vuoto)' { & 'Y:\windows\scrivi-iso-su-usb.ps1' -Iso 'D:\linux\Fedora-KDE-Desktop-Live-45-1.4.aarch64.iso' -Disco 1 -Modello 'TS256GSS' }
Run 'scrivi-iso-su-usb.ps1 su disco 0 (deve rifiutare)' { & 'Y:\windows\scrivi-iso-su-usb.ps1' -Iso 'D:\linux\Fedora-KDE-Desktop-Live-45-1.4.aarch64.iso' -Disco 0 -Modello 'SAMSUNG' }
Run 'scrivi-iso-su-usb.ps1 con modello sbagliato (deve rifiutare)' { & 'Y:\windows\scrivi-iso-su-usb.ps1' -Iso 'D:\linux\Fedora-KDE-Desktop-Live-45-1.4.aarch64.iso' -Disco 1 -Modello 'KINGSTON' }
Run 'secureboot-aggiungi-uefi-ca-2023.ps1 (senza -Conferma)' { & 'Y:\windows\secureboot-aggiungi-uefi-ca-2023.ps1' }

<#
Mostra lo stato del Secure Boot e di BitLocker (sola lettura, non modifica nulla).
Va eseguito da PowerShell come amministratore:   .\secureboot-stato.ps1
#>
$ErrorActionPreference = 'Continue'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) { throw 'Esegui da PowerShell come amministratore.' }
try { "Secure Boot attivo : $(Confirm-SecureBootUEFI)" } catch { "Secure Boot        : $_" }
try { "Setup Mode         : $((Get-SecureBootUEFI -Name SetupMode).Bytes[0])   (1 = chiavi vuote, firmware in Setup Mode)" } catch { "Setup Mode         : $_" }
$cerca = 'Microsoft Windows Production PCA 2011', 'Windows UEFI CA 2023', 'Microsoft Corporation UEFI CA 2011', 'Microsoft UEFI CA 2023',
         'Microsoft Option ROM UEFI CA 2023', 'Microsoft Corporation KEK CA 2011', 'Microsoft Corporation KEK 2K CA 2023', 'Lenovo'
foreach ($v in 'PK', 'KEK', 'db') {
    try {
        $s = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name $v -ErrorAction Stop).Bytes)
        "[$v]"; foreach ($c in $cerca) { if ($s.Contains($c)) { "   presente: $c" } }
    } catch { "[$v] vuoto o non leggibile" }
}
''
'Per avviare Linux (Fedora, Ubuntu...) con Secure Boot attivo nel [db] deve esserci: Microsoft UEFI CA 2023'
''
'BitLocker su C:'
manage-bde -status C: | Select-String 'Stato conversione|Conversion Status|Stato protezione|Protection Status|Protezioni con chiave|Key Protectors' -Context 0, 2
"Registro: AvailableUpdates = $((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot' -ErrorAction SilentlyContinue).AvailableUpdates)  UEFICA2023Status = $((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' -ErrorAction SilentlyContinue).UEFICA2023Status)"

<#
Aggiunge al database [db] del Secure Boot il certificato "Microsoft UEFI CA 2023", quello che firma
gli shim di Linux per ARM64 (verificato: lo shim BOOTAA64.EFI di Fedora 45 e' firmato con quel certificato).
Dopo, Windows e Fedora si avviano entrambi con Secure Boot ATTIVO, senza chiavi personali.

Usa il meccanismo ufficiale di Windows (KB5068202): valore di registro AvailableUpdates + attivita' pianificata
\Microsoft\Windows\PI\Secure-Boot-Update, che applica il pacchetto firmato da Microsoft
C:\Windows\System32\SecureBootUpdates\DBUpdate3P2023.bin. Non rimuove nulla: aggiunge un certificato.

PRIMA di eseguirlo:
  1. Il firmware deve avere le chiavi di fabbrica: BIOS (F2) > Security > Restore Factory Keys.
     (Se e' in Setup Mode con chiavi vuote questo script si ferma.)
  2. BitLocker su C: deve avere la protezione disattivata o sospesa, oppure devi avere la chiave di ripristino.

Uso (PowerShell come amministratore):
  .\secureboot-aggiungi-uefi-ca-2023.ps1            # solo controlli, non modifica nulla
  .\secureboot-aggiungi-uefi-ca-2023.ps1 -Conferma  # applica
NON PROVATO su questo portatile al momento della scrittura: lo script verifica il risultato e lo dice.
#>
param([switch]$Conferma)
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) { throw 'Esegui da PowerShell come amministratore.' }
function Db-Ha($nome) { try { [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name db).Bytes).Contains($nome) } catch { $false } }
$CA = 'Microsoft UEFI CA 2023'
$pkg = "$env:SystemRoot\System32\SecureBootUpdates\DBUpdate3P2023.bin"
$reg = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot'

$setup = try { (Get-SecureBootUEFI -Name SetupMode).Bytes[0] } catch { $null }
"Setup Mode: $setup   Secure Boot attivo: $(try { Confirm-SecureBootUEFI } catch { 'n/d' })"
if (Db-Ha $CA) { "Il certificato '$CA' e' GIA' nel db: non serve fare nulla. Puoi attivare Secure Boot nel BIOS."; return }
if ($setup -eq 1) { throw "Firmware in Setup Mode (chiavi vuote). Prima: BIOS > Security > Restore Factory Keys, poi riesegui." }
if (-not (Db-Ha 'Windows UEFI CA 2023') -and -not (Db-Ha 'Microsoft Windows Production PCA 2011')) { throw 'Il db non contiene i certificati Windows: ripristina le chiavi di fabbrica dal BIOS.' }
if (-not (Test-Path $pkg)) { throw "Pacchetto non trovato: $pkg (aggiorna Windows)." }
$bl = (manage-bde -status C: | Out-String)
if ($bl -match 'Protezione attivata|Protection On') {
    'ATTENZIONE: BitLocker ha la protezione ATTIVA. Sospendila prima:  manage-bde -protectors -disable C: -RebootCount 3'
    'oppure assicurati di avere la chiave di ripristino. Mi fermo.'; return
}
"Controlli superati. Pacchetto: $pkg ($((Get-Item $pkg).Length) byte)"
if (-not $Conferma) { 'Nessuna modifica fatta. Per applicare: aggiungi -Conferma'; return }

# 0x1000 = aggiungi "Microsoft UEFI CA 2023" al db. Non si imposta 0x4000, che lo limiterebbe ai PC
# che hanno gia' il certificato terze parti del 2011 (questo portatile non lo ha).
Set-ItemProperty -Path $reg -Name AvailableUpdates -Value 0x1000 -Type DWord
$task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\PI\' -TaskName 'Secure-Boot-Update' -ErrorAction SilentlyContinue
if ($task) { Start-ScheduledTask -TaskPath '\Microsoft\Windows\PI\' -TaskName 'Secure-Boot-Update'; 'Attivita'' Secure-Boot-Update avviata, attendo...' }
else { 'Attivita'' Secure-Boot-Update non trovata: il valore verra'' elaborato da Windows al prossimo riavvio o entro 12 ore.' }
for ($i = 0; $i -lt 30; $i++) { Start-Sleep 4; if (Db-Ha $CA) { break } }
"AvailableUpdates ora = 0x{0:X}" -f ((Get-ItemProperty $reg).AvailableUpdates)
if (Db-Ha $CA) {
    "FATTO: '$CA' e' nel db. Ora: BIOS > Security > Secure Boot = Enabled, poi verifica che partano sia Windows sia Fedora."
} else {
    "Il certificato non risulta ancora nel db. Riavvia Windows, riesegui .\secureboot-stato.ps1 e controlla."
    "Se dopo il riavvio manca ancora, vedi secureboot\LEGGIMI.txt (metodo alternativo)."
}

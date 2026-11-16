<#
Scrive una immagine ISO "raw" su un disco USB (come dd o Fedora Media Writer) e ne verifica lo SHA-256.
Serve per provare altre distro: su questo portatile Ventoy non avvia i kernel ARM64 recenti.
ATTENZIONE: CANCELLA TUTTO il disco indicato. Va eseguito da PowerShell come amministratore.

Esempio:
  Get-Disk | Format-Table Number,FriendlyName,BusType,Size          # trova il numero del disco USB
  .\scrivi-iso-su-usb.ps1 -Iso D:\linux\distro.iso -Disco 1 -Modello TS256GSS -Conferma

  -Modello   pezzo del nome del disco (FriendlyName): se non corrisponde lo script si ferma
  -Sha256    (facoltativo) hash atteso della ISO: viene controllato prima di scrivere
  -Conferma  obbligatorio per scrivere davvero; senza, mostra solo cosa farebbe
#>
param(
    [Parameter(Mandatory)][string]$Iso,
    [Parameter(Mandatory)][int]$Disco,
    [Parameter(Mandatory)][string]$Modello,
    [string]$Sha256,
    [switch]$Conferma
)
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) { throw 'Esegui da PowerShell come amministratore.' }
$isoItem = Get-Item -LiteralPath $Iso
$d = Get-Disk -Number $Disco
if ($d.BusType -ne 'USB') { throw "Il disco $Disco non e' USB ($($d.BusType)): rifiuto." }
if ($d.IsBoot -or $d.IsSystem) { throw "Il disco $Disco e' il disco di sistema: rifiuto." }
if ($d.FriendlyName -notlike "*$Modello*") { throw "Il disco $Disco si chiama '$($d.FriendlyName)', non contiene '$Modello': rifiuto." }
if ($isoItem.Length -gt $d.Size) { throw 'La ISO e'' piu'' grande del disco.' }
"Disco $Disco : $($d.FriendlyName)  $([math]::Round($d.Size/1GB,1)) GB  ($($d.NumberOfPartitions) partizioni)"
"ISO      : $($isoItem.FullName)  $([math]::Round($isoItem.Length/1MB)) MB"
if (-not $Conferma) { 'Prova a vuoto: aggiungi -Conferma per cancellare il disco e scrivere la ISO.'; return }

$sha = [Security.Cryptography.SHA256]::Create()
$in = [IO.File]::OpenRead($isoItem.FullName)
try { $isoHash = ($sha.ComputeHash($in) | ForEach-Object { $_.ToString('x2') }) -join '' } finally { $in.Close() }
"SHA-256 ISO: $isoHash"
if ($Sha256 -and $isoHash -ne $Sha256.ToLower()) { throw 'SHA-256 della ISO diverso da quello atteso: non scrivo.' }

$dp = Join-Path $env:TEMP 'scrivi-iso-diskpart.txt'
"select disk $Disco`r`nclean`r`nrescan`r`n" | Out-File $dp -Encoding ascii
diskpart /s $dp | Out-Null
if ((Get-Disk -Number $Disco).NumberOfPartitions -ne 0) { throw 'diskpart clean non ha svuotato il disco.' }

Add-Type -Namespace ScriviIso -Name K -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string n, uint a, uint s, System.IntPtr sec, uint c, uint f, System.IntPtr t);
'@
# GENERIC_READ|GENERIC_WRITE = 0xC0000000, FILE_FLAG_WRITE_THROUGH = 0x20000000
$h = [ScriviIso.K]::CreateFile("\\.\PhysicalDrive$Disco", [uint32]3221225472, 3, [IntPtr]::Zero, 3, [uint32]536870912, [IntPtr]::Zero)
if ($h.IsInvalid) { throw "Apertura del disco fallita (errore $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))." }
$fs = New-Object IO.FileStream($h, [IO.FileAccess]::ReadWrite, 1)
$in = [IO.File]::OpenRead($isoItem.FullName)
try {
    $buf = New-Object byte[] (4MB); [long]$tot = 0; [long]$len = $in.Length
    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
        $w = $n
        if ($n % 512) { $w = $n + (512 - $n % 512); [Array]::Clear($buf, $n, $w - $n) }   # i dischi raw vogliono blocchi interi: riempio di zeri
        $fs.Write($buf, 0, $w); $tot += $n
        Write-Progress -Activity 'Scrittura' -PercentComplete ([math]::Min(100, [int](100 * $tot / $len)))
    }
    $fs.Flush()
    "Scritti $tot byte. Verifica in corso..."
    $fs.Position = 0; $sha2 = [Security.Cryptography.SHA256]::Create(); [long]$rem = $len
    while ($rem -gt 0) {
        $n = $fs.Read($buf, 0, $buf.Length); if ($n -le 0) { throw 'Lettura di verifica interrotta.' }
        [int]$use = if ($rem -lt $n) { [int]$rem } else { $n }
        [void]$sha2.TransformBlock($buf, 0, $use, $null, 0); $rem -= $use
    }
    [void]$sha2.TransformFinalBlock($buf, 0, 0)
    $diskHash = ($sha2.Hash | ForEach-Object { $_.ToString('x2') }) -join ''
} finally { $in.Close(); $fs.Close() }
"SHA-256 disco: $diskHash"
if ($diskHash -eq $isoHash) { 'OK: il disco e'' identico alla ISO.' } else { throw 'ERRORE: il disco NON corrisponde alla ISO.' }
Update-Disk -Number $Disco

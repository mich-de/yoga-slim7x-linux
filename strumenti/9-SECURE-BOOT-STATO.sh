#!/bin/bash
# Mostra lo stato del Secure Boot visto da Linux (sola lettura) e ricorda la procedura. Non modifica nulla.
. "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
apri_terminale "$@"
diventa_root "$@"

LD=$(logdir); L="$LD/secureboot-$(ts).txt"
log() { echo "$*" | tee -a "$L"; }
E=/sys/firmware/efi/efivars
byte() { od -An -tu1 -j4 -N1 "$1" 2>/dev/null | tr -d ' '; }
log "=== Secure Boot $(date)"
log "SecureBoot=$(byte $E/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c)  SetupMode=$(byte $E/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c)  (1 = attivo)"
command -v mokutil >/dev/null && mokutil --sb-state 2>&1 | tee -a "$L"
for v in PK KEK db; do
    f=$(ls $E/$v-* 2>/dev/null | head -n1)
    if [ -n "$f" ]; then log "$v: $(strings -n 8 "$f" 2>/dev/null | grep -E 'Microsoft|Windows|Lenovo|UEFI CA|KEK' | sort -u | tr '\n' ';')"
    else log "$v: vuoto"; fi
done
s=$(ls /boot/efi/EFI/*/shimaa64.efi 2>/dev/null | head -n1)
[ -n "$s" ] && command -v pesign >/dev/null && { log "Firma dello shim $s:"; pesign -S -i "$s" 2>&1 | grep -E 'common name' | tee -a "$L"; }
log ""
log "Procedura per avere Secure Boot ATTIVO con Windows + Fedora: vedi secureboot/LEGGIMI.txt"
log "(in breve: BIOS > Restore Factory Keys; da Windows windows/secureboot-aggiungi-uefi-ca-2023.ps1; BIOS > Secure Boot Enabled)"
sync

# Linux sul Lenovo Yoga Slim 7x (83ED, Snapdragon X Elite)

Repository **privato**: contiene file proprietari presi dal Windows di questo portatile (firmware Qualcomm, driver audio, taratura Dolby e calibrazione) e log con identificativi dell'hardware. Non renderlo pubblico e non ridistribuirlo.

Stato del lavoro, cause trovate e prossimi passi: [`HANDOFF.md`](HANDOFF.md). Fatti stabili: [`memory.md`](memory.md).

## Contenuto
| Cartella | Cosa c'è |
|---|---|
| `strumenti/` | Copia della partizione STRUMENTI della chiavetta (Y: in Windows): script 1–12, automatismi in `avvio/`, firmware, audio, kernel 7.2.11 con la correzione tastiera, reverse dell'audio di Windows (`audio-auto/REVERSE-AUDIO-WINDOWS.md`, `tools/re-audio/`), Secure Boot, log. Indice: `strumenti/LEGGIMI.txt`. |
| `chiavetta-efi/` | Menu GRUB della chiavetta (`grub.cfg`), initrd aggiuntivo (`strumenti.cpio`) con il suo sorgente (`initrd/`, `mk_cpio.py`) e le versioni precedenti del menu. |
| `sorgenti/windows/` | Script PowerShell usati da Windows per scrivere la ISO, creare la partizione, aggiornare la partizione EFI, leggere i settori grezzi. |
| `sorgenti/vm/` | Prova in macchina virtuale (QEMU in WSL) e collaudo degli script. |
| `sorgenti/analisi/` | Estrazione del device tree dal kernel, ispezione dell'initrd, confronto di device tree. |

## In breve
- Tastiera e touchpad: funzionano solo con il bus I2C `b80000` a 100 kHz (correzione nel kernel caricato dal menu della chiavetta).
- Audio: funziona, ma non è equivalente a Windows (Dolby Atmos e protezione degli altoparlanti mancano su Linux).
- La chiavetta fa tutto da sola: prima voce del menu, poi installazione di Fedora dal programma di installazione.

Non incluso: la ISO di Fedora (`Fedora-KDE-Desktop-Live-45-1.4.aarch64.iso`, sha256 `46a73d4c0a82a77551311ab1589255ecac51b5ce311b4fc84577f5ede5a44f5c`).

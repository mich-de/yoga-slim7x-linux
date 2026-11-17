# Audio Yoga

Profili audio per il Lenovo Yoga Slim 7x su Fedora (ARM64). Il suono degli altoparlanti passa per il codice
originale delle due librerie Dolby usate da Windows su questo portatile (`DolbyAPOVR.dll` per i contenuti e
`DolbyAPOvlldp150.dll` per l'altoparlante, versione 3.30812.891.0), con la taratura Lenovo di questo modello.
I file non vengono modificati: sono caricati in memoria così come sono e accettati solo se la loro impronta
SHA-256 è quella nota.

**Questo repository non contiene nessun file Dolby né la taratura**: servono il proprio portatile e il proprio
Windows. Uso personale, sullo stesso hardware che ha la licenza.

## Che cosa fa
- Uscita PipeWire "Audio Yoga", messa prima di "Altoparlanti potenziati".
- Sei profili della taratura: Dinamico, Film, Musica (predefinito, come in Windows), Gioco, Voce, Spento.
- Surround virtuale, dialoghi più chiari e volume uniforme, con i valori di ogni profilo o scelti a mano.
- Equalizzatore a 20 bande (da −12 a +12 dB) sul banco di filtri della libreria, con curve pronte.
- "Volume massimo": +6 dB prima del regolatore dell'altoparlante, che trattiene i suoni forti.
- Se i file privati mancano o non sono quelli ammessi, l'audio passa invariato; con il solo DLL
  dell'altoparlante restano profili ed equalizzatore.
- Ritardo: 690 campioni (14 ms) più il blocco di PipeWire.

## File
| File | Compito |
|---|---|
| `pe.c`, `pe.h` | carica un DLL di Windows ARM64, verifica l'impronta, collega le funzioni importate |
| `indirizzi.h` | indirizzi delle funzioni della libreria per questa versione del DLL |
| `vlldp.c`, `vr.c`, `motore.c` | le due librerie e i profili |
| `audio_yoga_ladspa.c` | plugin LADSPA per PipeWire (blocchi da 256 campioni) |
| `audio-yoga.conf` | filtro PipeWire, servizio utente `audio-yoga.service` |
| `audio_yoga.py` | app (PySide6): finestra e icona nel vassoio |
| `profili.py` | traduce la taratura in `profili.txt` (dato privato) |
| `../../avvio/audio-yoga.sh` | installazione automatica dal kit |

## Costruire e provare
```
make                                             # serve gcc e ladspa-devel
./prova1 <cartella dei DLL> <elenco impronte>    # il codice originale gira
./prova2 <cartella dei DLL> <elenco impronte>    # elabora blocchi, ripetibile
./prova3 <cartella dei DLL> <elenco impronte> <profili.txt> music   # curva a 20 bande entro 0,5 dB
AUDIO_YOGA_DIR=<cartella privata> ./prova_plugin ./audio_yoga.so   # plugin con blocchi irregolari
bash prove/prova_pipewire.sh <cartella privata>  # dentro PipeWire su un'uscita finta, senza suono
```
Cartella privata: `DolbyAPOvlldp150.dll`, `DolbyAPOVR.dll`, `sha256-dll-yoga.txt`, `profili.txt`
(`python3 profili.py taratura.json > profili.txt`).

## Limiti noti
- Gli indirizzi in `indirizzi.h` valgono solo per questa versione dei DLL: se Windows aggiorna il driver Dolby
  vanno ritrovati (il motore rifiuta i file con impronta diversa e lascia passare l'audio).
- Il volume di sistema agisce prima del motore (in Windows dopo) e il legame fra volume e regolatore non è
  riprodotto.
- Cuffie e Bluetooth non sono elaborati.

## Riconoscimenti
Il caricamento del DLL deriva da `sp11_vlldp_pe_loader.h` del progetto
[geocausa/SP11X1e-audio](https://github.com/geocausa/SP11X1e-audio) (BSD-2-Clause), che per primo ha fatto
girare questa libreria su Linux ARM64 sul Surface Pro 11. Dolby e Dolby Atmos sono marchi di Dolby Laboratories;
questo progetto non è affiliato né approvato da Dolby.

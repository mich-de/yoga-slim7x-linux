# 09 - Far girare i DLL Dolby originali (ARM64 PE) su Fedora 45 aarch64

Fase di studio: niente installato, niente costruito. Legenda: **visto** (comando/fonte),
**dedotto** (ragionamento su dati visti), **ignoto**.
File di lavoro: `$D/work/09/` (imports.py, imports-apo.txt, imports-svc.txt, repoquery.txt,
wine.spec, ANN-*.txt, spec-*.txt, wine-dlls.txt).
`$D = /tmp/claude-1000/-run-media-liveuser-Volume-linux/747a0e5d-c8cd-40ba-973d-676e005c4581/scratchpad/dolby`

## Sintesi

- Su Fedora 45 aarch64 **Wine non c'è** (né wine né wine-core): il pacchetto Fedora 11.21 ha
  `ExclusiveArch: %{ix86} x86_64` (visto). Il kernel usa pagine da 4 KiB (visto), quindi Wine
  ARM64 qui può funzionare: serve solo procurarselo (container Debian, o ricompilazione).
- Delle funzioni di sistema importate dai DLL di elaborazione, in Wine manca **solo audioeng.dll**
  (2 funzioni: `AERT_Allocate`, `AERT_Free`), facile da fornire con un DLL nostro (visto).
- Il programma ospite PE ARM64 si compila con pacchetti Fedora: `zig` (0.16.0) con il bersaglio
  aarch64-windows-gnu, oppure clang/lld/llvm 23 (+ librerie da creare); llvm-mingw è l'alternativa
  scaricabile (74 MiB).
- Il progetto gemello SP11 ha già fatto girare DLL Dolby ARM64 originali (altri DLL, stessa
  famiglia) su Linux con un caricatore PE minimo: la strada è percorribile.
- Esperimento consigliato: Wine 10.0 arm64 di Debian in un container podman, più un piccolo
  `apohost.exe` che elabora un file WAV offline (niente suono).

## 1. Wine su aarch64 in Fedora 45

| Fatto | Stato | Fonte |
|---|---|---|
| `getconf PAGESIZE` = 4096; `CONFIG_ARM64_4K_PAGES=y`, VA 48 bit | visto | comando, /boot/config-7.2.11-300.fc45.aarch64 |
| `dnf repoquery 'wine*'` sui repo fedora/updates aarch64: solo `wineglass` e `winetricks`, nessun `wine`/`wine-core` | visto | repoquery.txt |
| wine.spec Fedora (rawhide, = f45): Version 11.21; `ExclusiveArch: %{ix86} x86_64` con il commento "Wine 9.15 and higher requires ARM MinGW binaries (dlltool)" | visto | src.fedoraproject.org/rpms/wine, wine.spec righe 49, 101-105 |
| Lo spec contiene già i rami `%ifarch aarch64` (clang, lld, `aarch64-windows`) | visto | wine.spec righe 33-36, 112-114 |
| Flathub `org.winehq.Wine`: solo x86_64 | visto | API flathub `/api/v2/summary/org.winehq.Wine` |
| Debian sid/trixie: `libwine` arm64 10.0 (deb 143 MB, installato circa 968 MB) con DLL PE in `aarch64-windows/` (ntdll, ole32, avrt, rtworkq, mmdevapi...) | visto | packages.debian.org/sid/arm64/libwine (+ filelist) |
| Wine 9.0: "the completion of the PE/Unix separation means that it's possible to run existing Windows binaries on ARM64" | visto | ANNOUNCE.md wine-9.0 righe 63-66 |
| Wine 10.0: "ARM64 support requires the system page size to be 4K... 16K or 64K pages is not supported" | visto | ANNOUNCE.md wine-10.0 righe 45-47 |
| Wine 11.0: emulazione di pagine da 4K su host da 16K/64K, "Using a 4K-page kernel is strongly recommended" | visto | ANNOUNCE.md wine-11.0 righe 78-82 |
| I DLL Dolby sono `pei-aarch64-little` (ARM64 puro, non ARM64EC), quindi Wine aarch64 li carica senza emulazione | visto (objdump) / dedotto | dis/*.hdr.txt |

Come procurarsi Wine ARM64 (nessuna via è "dnf install"):
1. **Container Debian sid arm64 con podman** (podman e toolbox sono già presenti, visto): `apt install wine`
   circa 1-1,2 GB nello storage dei container (`~/.local/share/containers`, overlay in RAM; 4,6 GB liberi su `/`,
   15 GB in /tmp; visto con df). Il socket PulseAudio `/run/user/1000/pulse/native` (pipewire-pulse)
   si può montare nel container (visto: esiste). Versione 10.0: sufficiente (ARM64 completo dalla 9.0).
   Questa è la via più rapida.
2. **Ricompilare l'SRPM Fedora 11.21 togliendo l'esclusione aarch64**: ora Fedora ha `llvm-dlltool`, `lld-link`
   e clang 23 (visto con `dnf repoquery -l llvm lld`), che erano il motivo dell'esclusione. Riuscita **ignota**;
   circa 1 ora di compilazione e 3-4 GB di spazio di lavoro (dedotto). Da usare se si vuole un Wine nativo Fedora e durevole.
3. Compilare Wine upstream con llvm-mingw: equivalente al punto 2, più lavoro manuale.

## 2. Ospitare l'oggetto COM in-process (programma PE ARM64)

Visto: tutti i DLL di elaborazione esportano solo `DllCanUnloadNow, DllGetClassObject,
DllRegisterServer, DllUnregisterServer` (hdr.txt, tabella Ordinal/Name). L'INF registra il wrapper
`DolbyDax3Apo.dll` (ThreadingModel "Both", `dax3_swc_aposvc_arm64.inf` righe 96-101) come SFX/MFX/OSFX/OMFX
dell'endpoint (`dax3_ext_qc.inf` righe 473-493). Il wrapper carica a sua volta i DLL di
elaborazione per nome relativo (stringhe `\DolbyAPOv251.dll`, `\DolbyAPOvlldp150.dll`, `\Dax3Ref.dll`... e
chiave `SOFTWARE\Dolby\Wrapper\`, visto in DolbyDax3Apo.dll.str16.txt).

Sequenza dell'ospite (dedotta dal modello APO pubblico di Windows; ordine dei vtable da verificare):
1. `CoInitializeEx`; `LoadLibraryW(DLL)`; `GetProcAddress("DllGetClassObject")` con il CLSID
   (per il wrapper i CLSID V2 0EBD86xx dell'endpoint, visti in work/01/reg_endpoint_fx.txt;
   per i singoli DLL di elaborazione il CLSID è **ignoto** e va ricavato dalla tabella delle class factory, compito 02).
2. `IClassFactory::CreateInstance(IID_IAudioProcessingObject)`.
3. `IAudioProcessingObject::Initialize(sizeof(APOInitSystemEffects3), &init)`, con finti
   `IPropertyStore` (endpoint e FX, valori tratti dal dump di registro `FxProperties` di Windows,
   work/01), un finto `IMMDeviceCollection` e il modo `AUDIO_SIGNALPROCESSINGMODE_DEFAULT`. Il gemello SP11
   documenta che "a small COM facade for the APO initialization context is sufficient" (visto,
   docs/findings/2026-08-09-...BREAKTHROUGH.md, sezione "DAP activation").
4. `IsInputFormatSupported`/`IsOutputFormatSupported` con un nostro `IAudioMediaType` (float32, 48 kHz, stereo).
5. `IAudioProcessingObjectConfiguration::LockForProcess` con `APO_CONNECTION_DESCRIPTOR` (buffer esterni, 480 frame).
6. Ciclo `IAudioProcessingObjectRT::APOProcess` a blocchi di 10 ms.

Allocatore del motore audio: `AERT_Allocate`/`AERT_Free` hanno la firma
`HRESULT AERT_Allocate(size_t, void**)` / `void AERT_Free(void*)` (visto: DolbyAPOv251 0x180054838-0x180054854,
argomento in x0, puntatore di uscita in x1, verifica `tbnz w0,#31`). Basta un nostro `audioeng.dll` di 2 funzioni
(VirtualAlloc + VirtualLock); non si tocca nessun binario Dolby.

Compilatori (repoquery, visto):

| Strumento | Dove | Dimensione | Note |
|---|---|---|---|
| `zig` 0.16.0 + `zig-libs` | repo fedora | 22,5 + 172,6 MiB | `zig cc -target aarch64-windows-gnu`; contiene sorgenti/def di mingw-w64, `mmdeviceapi.h`, `propsys.h`, `audioapotypes.h`; **manca** `audioenginebaseapo.h` (IAudioProcessingObject*), da dichiarare a mano (~100 righe dalla documentazione Microsoft). Supporto arm64 di zig-mingw: dedotto, da provare per primo. |
| clang 23.1.5 + lld + llvm (llvm-dlltool, lld-link) | repo updates | 67 + 83 MiB | bersaglio aarch64-pc-windows-msvc o -gnu con `-nostdlib`; mancano CRT e librerie di import mingw arm64 (Fedora ha solo `mingw64-*`/`ucrt64-*` x86_64), da generare con llvm-dlltool dai .def. Fattibile ma più manuale. |
| llvm-mingw 20261104 ucrt ubuntu-22.04-aarch64 | GitHub mstorsjo | 74 MiB tar.xz | toolchain completa aarch64-w64-mingw32; via di riserva. |
| winegcc/winelib | - | - | non disponibile (niente Wine Fedora). |

## 3. Import dei DLL e copertura in Wine

Metodo: `work/09/imports.py` sugli hdr.txt (visto); confronto nome per nome con gli `.spec`
di Wine master (gitlab.winehq.org, visto).

Elaborazione (DolbyDax3Apo, DolbyAPOv251/v2100/VR, vlldp*, Dax3Ref), insieme:

| DLL | Funzioni | Wine |
|---|---|---|
| kernel32 | 142 (heap, CS/SRW/CV, thread, Fls, file mapping/mutex/event con nome, risorse, `RtlUnwindEx`, `RtlLookupFunctionEntry`, `VirtualLock`...) | tutte presenti, nessuno stub (visto) |
| advapi32 | 15 (Reg*, `EventRegister/EventWriteString`, `ConvertStringSecurityDescriptorToSecurityDescriptorW`) | presenti (ETW inoltrato a ntdll) |
| ole32 | 10 (`CoCreateInstance`, `CoTaskMem*`, `PropVariantClear`...) | presenti |
| oleaut32 | per ordinale 2, 6, 7, 161, 163, 186, 277, 314 = SysAllocString, SysFreeString, SysStringLen, LoadTypeLib, RegisterTypeLib, UnRegisterTypeLib, VarUI4FromStr, VarBstrCmp | presenti (visto in oleaut32.spec) |
| user32 | CharNextW, CharUpperBuffW, UnregisterClassW | presenti |
| shlwapi | PathRemoveFileSpecW | presente |
| avrt | AvSetMmThreadCharacteristicsW, AvRevert... | presenti (avrt.spec) |
| rtworkq | RtwqCreateAsyncResult, RtwqPutWorkItem | presenti (rtworkq.spec) |
| api-ms-win-mm-misc-l1-1-0 | mmio* (7) | apiset -> winmm (`apisetschema.spec` mappa `...-l1-1-1`; la risoluzione per prefisso è dedotta); mmio* presenti |
| **audioeng** | AERT_Allocate, AERT_Free | **assente in Wine** (`dlls/audioeng` 404, non nell'elenco dei 744 dlls): serve un DLL nostro |

Il CRT è statico (nessun import di vcruntime/ucrtbase; `GetCommandLineA`, `Fls*` in kernel32: visto).

Servizio e controllo (DAX3API.exe, Dax3DapControl, DAXSSID, CaptureStreamMonitor), per il seguito:
rpcrt4 (NdrClientCall3, NdrServerCall2/All, RpcServerRegisterIf3: presenti), propsys
(`InitPropVariantFromInt32Vector` e `PropVariantGetElementCount` sono **stub** in Wine; il resto è presente),
cfgmgr32/setupapi (presenti, ma su Wine descrivono dispositivi di Wine, non l'hardware reale: comportamento di
DAXSSID **ignoto**), mf/mfplat, crypt32, wtsapi32, gestione servizi, `RegisterPowerSettingNotification`: presenti.
Il servizio non serve al primo esperimento.

Canale APO <-> servizio: memoria condivisa `Global\` con mutex/eventi (`SharedMemoryController.cpp`,
`SharedMemorySessionClient2.cpp`, messaggi `CreateFileMapping failed`..., visto in DolbyAPOv251.str16.txt).
Wine supporta oggetti con nome; senza servizio l'APO stampa "Dolby PP module not found - legacy mode:
processing audio" (visto): quale profilo applichi in quel caso è **ignoto**.

## 4. Alternative a Wine: caricatore PE dentro un processo Linux

Fatto concreto: il gemello SP11 (`dolby-port/sp11_vlldp_pe_loader.h`, `linux-harness/`) mappa il PE, applica
le rilocazioni DIR64, imposta x18 = TEB finto con `TEB+0x58` = puntatore TLS, e collega le import a funzioni C
Linux. Dichiara elaborazione reale con DLL Dolby originali (bit-exact in bypass) (visto, finding 2026-08-09).
Attenzione: quel codice scrive anche istruzioni dentro l'immagine (`pret`, `pret0`), cioè modifica il binario
in memoria: fuori dal perimetro di questo studio. Un caricatore pulito deve solo risolvere le import.

Requisiti tecnici (visti nei nostri DLL, salvo dove indicato):
- **TEB in x18**: `ldr x8,[x18,#88]` (TLS, 6 volte) e `ldr x17,[x18,#16]` (StackLimit per __chkstk) in DolbyAPOv251;
  9-10 accessi in DolbyDax3Apo e vlldp. Su Linux x18 è un registro temporaneo: il codice di raccordo va compilato
  con `-ffixed-x18`, e x18 va salvato e ripristinato a ogni passaggio Windows->Linux (glibc, gestori di segnale) (dedotto).
- **TLS statico** (directory TLS presente, Entry 9) e callback; **Fls***; thread creati dal DLL
  (`CreateThread`, ciclo di sorveglianza della memoria condivisa) devono ricevere ognuno il proprio TEB.
- **Eccezioni**: `.pdata` presente (Entry 3), import di `RtlUnwindEx`, `RtlLookupFunctionEntry`, `RaiseException`:
  se il codice lancia eccezioni C++ servono un vero unwinder ARM64 SEH e un gestore di frame. Un caricatore
  minimo regge solo se nel percorso normale non si lancia nulla (**ignoto**).
- **ABI**: AAPCS64 è quasi uguale; differenze: `long` a 32 bit, `wchar_t` a 16 bit, variadiche Windows
  (i float passano nei registri interi). CFG attivo (DllCharacteristics 0x4160, Load Config presente): i puntatori
  di controllo restano di norma no-op (dedotto).
- 86 istruzioni `svc #0x3` in DolbyAPOv251, sempre dopo un salto incondizionato (codice irraggiungibile o trappola):
  su Linux, se eseguite, diventerebbero syscall con numero in x8. Significato **ignoto**; da tenere d'occhio.
- Circa 200 funzioni Win32 da emulare, più la semantica degli oggetti con nome per la memoria condivisa.
- "loadlibrary" di T. Ormandy: solo x86 a 32 bit (dedotto, noto); non utile qui.

Quando conviene: dopo aver capito con Wine la sequenza esatta delle chiamate. Il vantaggio è che il DLL gira
**dentro** un plugin LADSPA/filter-chain, senza processo esterno né latenza aggiunta. Costo alto e rischio di
divergenze sottili. Wine fa da riferimento per validarlo.

## 5. Ponte audio processo ospite <-> PipeWire

PipeWire 1.6.9, pipewire-pulse, pipewire-jack e LADSPA/LV2 nei repo (visto). Schema comune: null-sink
virtuale "Dolby" come uscita predefinita -> ospite -> altoparlanti reali.

| Opzione | Latenza attesa (dedotta) | Complessità | Note |
|---|---|---|---|
| A. `pw-cat --record` dal monitor -> stdin di `wine apohost.exe` -> stdout -> `pw-cat --playback` | 10-40 ms in regime; può crescere fino a ~170 ms se la pipe si riempie (64 KiB a 384 kB/s) | bassa | stesso grafo e stesso clock, nessuna deriva; ideale per la prova |
| B. ospite WASAPI in Wine (winepulse.drv su pipewire-pulse), cattura del monitor + resa | 20-50 ms (periodi winepulse + pulse) | media | tutto dentro Wine; la cattura dei monitor tramite winepulse è da verificare (**ignoto**) |
| C. memoria condivisa: file in /dev/shm aperto da Wine come `Z:\dev\shm\...` + `CreateFileMapping`, con un filtro nativo `pw_filter` o un plugin LADSPA in filter-chain | 1 quantum (5,3 ms a 256/48k) + elaborazione | alta | serve sincronizzazione (attesa attiva o eventfd tramite unixlib); prestazioni migliori |
| D. JACK dentro Wine | - | - | winejack.drv non esiste più (assente dall'elenco dlls); wineasio richiede un host ASIO: non conviene |
| E. caricatore PE dentro il plugin LADSPA (sez. 4) | 0 aggiunta | molto alta | soluzione finale "pulita", non un ponte |

## 6. Esperimento minimo proposto

Obiettivo: dimostrare (o smentire) che `DolbyAPOv251.dll` (poi il wrapper DolbyDax3Apo) si istanzia,
si inizializza ed elabora audio sotto Wine ARM64 su questo portatile. Tutto offline, da file WAV a file WAV:
nessun suono, nessuna modifica a PipeWire.

Passi:
1. `dnf install zig` (circa 195 MiB nell'overlay in RAM). In alternativa llvm-mingw in /tmp.
2. `podman run` di `debian:sid` arm64 e `apt install --no-install-recommends wine` (circa 1,2 GB; storage
   dei container eventualmente spostato su /tmp). Controllo: `wine cmd /c ver` e un hello.exe ARM64 compilato con zig.
3. Scrivere `audioeng.dll` (AERT_Allocate/AERT_Free) e `apohost.exe` (sez. 2: facciate IPropertyStore,
   IMMDeviceCollection, IAudioMediaType; interfacce APO dichiarate a mano) con log a ogni HRESULT.
4. Copiare i 14 binari in `C:\dolby\` nel prefix (copia di lavoro, gli originali restano intatti); caricare prima un
   DLL di elaborazione, poi il wrapper (che cerca i DLL fratelli nella sua cartella).
5. Ingressi: sinusoide 1 kHz -20 dBFS, sweep, rumore rosa, 48 kHz float stereo.
6. In seguito: confronto con un riferimento catturato su Windows dello stesso portatile (stesso profilo).

Criteri di successo, a gradini: (a) `LoadLibrary` + DllMain OK; (b) `DllGetClassObject`/`CreateInstance` S_OK;
(c) `Initialize` S_OK; (d) `LockForProcess` S_OK; (e) `APOProcess` produce un'uscita deterministica, finita,
non nulla e diversa dall'ingresso (o bypass dichiarato); (f) somiglianza misurabile con il riferimento di Windows.
Il risultato è negativo se il processo si ferma in (b)-(d) per dipendenze che non si possono fornire senza
toccare i binari o aggirare controlli.

Spazio e tempo: circa 1,5 GB tra RAM e overlay, circa mezza giornata (dedotto).

Rischi principali:
1. **Parametri/profilo**: senza DAX3API l'APO va in "legacy mode"; la taratura reale arriva dal servizio
   tramite memoria `Global\` e dalle proprietà FX. Far girare DAX3API.exe sotto Wine è un secondo passo con
   esito **ignoto** (enumerazione dei dispositivi via cfgmgr32/DAXSSID su Wine). I controlli di licenza o
   d'identità non vanno aggirati: se bloccano, la strada si ferma lì.
2. Facciate APO incomplete (servizi di APOInitSystemEffects3, logging, notifiche): il gemello ce l'ha fatta su
   DLL simili, ma l'ordine dei vtable va verificato.
3. Tempo reale: thread Wine senza priorità RT; `AvSetMmThreadCharacteristicsW` di Wine non alza la priorità (dedotto).
4. Wine 10.0 di Debian rispetto a 11.x: differenze minori per ARM64 puro (dedotto).
5. `svc #0x3` e percorsi d'errore rari (sez. 4).
6. Uso personale e interoperabilità sullo stesso dispositivo con licenza: valutazione legale a carico del proprietario.

## Fonti

- Fedora wine.spec: https://src.fedoraproject.org/rpms/wine/raw/rawhide/f/wine.spec (copia in work/09/wine.spec)
- Wine ANNOUNCE 9.0/10.0/11.0: https://gitlab.winehq.org/wine/wine/-/raw/wine-9.0/ANNOUNCE.md (e wine-10.0, wine-11.0)
- Wine spec dei DLL: https://gitlab.winehq.org/wine/wine/-/raw/master/dlls/<dll>/<dll>.spec ; apiset:
  dlls/apisetschema/apisetschema.spec ; elenco dlls: API GitLab repository/tree?path=dlls
- Bug Wine su pagine da 16K (Asahi): https://list.winehq.org/archives/list/wine-bugs@list.winehq.org/thread/OIK2DBX7Y2DUNXLBWYU5TPO3M4CGOYXE ;
  https://asahilinux.org/docs/Broken-Software
- Debian libwine arm64: https://packages.debian.org/sid/arm64/libwine (+ /filelist)
- Flathub Wine: https://flathub.org/api/v2/summary/org.winehq.Wine
- llvm-mingw: https://api.github.com/repos/mstorsjo/llvm-mingw/releases/latest
- Progetto gemello: $T/docs/findings/2026-08-09-ASAR-WINDOWS-DOLBY-LINUX-HOST-BREAKTHROUGH.md,
  $T/dolby-port/sp11_vlldp_pe_loader.h, $T/dolby-port/linux-harness/
- Locali: $D/dis/*.hdr.txt, *.str16.txt, *.dis.txt; $D/pkg/*.inf; $D/work/01/reg_endpoint_fx.txt

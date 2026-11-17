# Dolby Atmos (DAX3) del Yoga Slim 7x: architettura e registrazione (compito 01, 2026-11-17)

Fonti: INF in `$D/pkg`, hive `SOFTWARE` e `SYSTEM` di `/mnt/win` (ControlSet001 = Current), stringhe/import/export dei 14 binari in `$D/bin`, rizin su `DolbyDax3Apo.dll`. Solo lettura statica: nulla è stato eseguito.
Legenda: **visto** (fonte citata), **dedotto**, **ignoto**. `$D` = scratchpad `.../scratchpad/dolby`; file di lavoro in `$D/work/01` (INF convertite in UTF-8, dump del registro, script `hivdump.sh`).

## 0. Risposta breve
Gli altoparlanti interni (endpoint "Altoparlanti", `{72a99614-9bc3-4e8f-98a7-30283009ad51}`) passano per **due APO Dolby annidati in un wrapper**:
- SFX (effetto di flusso) `{0EBD8605}` → `DolbyDax3Apo.dll` (wrapper) → carica **`DolbyAPOVR.dll`** `{E77F483A}` = elaborazione dei contenuti ("cp": DAP2 + virtualizzatore/spatial "dahp").
- MFX (effetto di modalità) `{0EBD8606}` → `DolbyDax3Apo.dll` → carica **`DolbyAPOvlldp150.dll`** `{5CA784EC}` = elaborazione del dispositivo ("vlldp", libreria VLLDP v1.5).
- EFX (endpoint) = **non Dolby**: `{697DA8EE}` Proxy APO Qualcomm (`ProxyAPO.dll`).
Versione di tutto il pacchetto APO: **3.30812.891** (DriverVer 3.30812.891.1, FileVersion dei binari 3.30812.891.0). Taratura: `AUCD_DEV_0C29_SUBSYS_IDEA4001_ADCM_SUBSYS_IDEA4001.xml` (xml_version 3.7.1, dtt 4.3.0.5, sezioni `tuning-cp` e `tuning-vlldp` per profilo).

## 1. Pacchetti INF (**visto**)

### 1a. `dax3_swc_aposvc_arm64.inf` (oem117.inf), classe AudioProcessingObject `{5989fce8-…}`, DriverVer 10/30/2025 3.30812.891.1
- Hardware ID: `SWC\VEN_DOLBY&PID_DAX3APOSVC` (componente software, aggiunto dall'INF di estensione).
- Copia in DirID 13 (DriverStore, `dax3_swc_aposvc_arm64.inf_arm64_d496b58e814ffb00`): i 14 binari + `Default_settings.xml` + `default_settings.json`. `PETrust=true` sulle 10 DLL di APO.
- Servizio `DolbyDAXAPI` ("Dolby DAX API Service"): tipo 0x10 (processo proprio), avvio automatico (2), `%13%\DAX3API.exe`.
- Classi COM (tutte `ThreadingModel=Both`, registrate con HKR → chiave software del dispositivo, vedi 2b) e APO (`AudioEngine\AudioProcessingObjects`, `APOInterface0={FD7F2B29…}` = IAudioProcessingObject):

| CLSID | Nome | DLL | Flags |
|---|---|---|---|
| `{0EBD8605-17BB-4AE7-AD76-E86F99A425E9}` | WRAPPER SFX (V2) | DolbyDax3Apo.dll | 0xC |
| `{0EBD8606-…}` | WRAPPER MFX (V2) | DolbyDax3Apo.dll | 0xC |
| `{0EBD8607-…}` | WRAPPER EFX (V2) | DolbyDax3Apo.dll | 0xC |
| `{0EBD8611-…}` | WRAPPER Offload SFX (V2) | DolbyDax3Apo.dll | 0xC |
| `{0EBD8612-…}` | WRAPPER Offload MFX (V2) | DolbyDax3Apo.dll | 0xC |
| `{D9916FA0-99F7-11E7-BF21-6C0B849889E1}` | DAPv251 | DolbyAPOv251.dll | 0xC |
| `{EFC7A7B3-40A7-4601-ABC1-878CD5EAE544}` | DAPv2100 | DolbyAPOv2100.dll | 0xC |
| `{1BEDAECC-55F6-4149-95D9-A707A2FB4134}` | DAPv2100 Lite | DolbyAPOv2100.dll | 0xC |
| `{E77F483A-E3A7-4647-B3AB-51FD990F55BA}` | DAPVR | DolbyAPOVR.dll | 0xC |
| `{D9916F9E-99F7-11E7-BF21-6C0B849889E1}` | VLLDP | DolbyAPOvlldp.dll | 0xE |
| `{D9916F9C-99F7-11E7-BF21-6C0B849889E1}` | VLLDP120 | DolbyAPOvlldp120.dll | 0xE |
| `{6E4DD785-E58A-4A6A-81D9-5EB9EB434EDA}` | VLLDP130 | DolbyAPOvlldp130.dll | 0xE |
| `{97ACD2AB-83EC-494B-9FE4-922BCE1BD691}` | VLLDP140 | DolbyAPOvlldp140.dll | 0xE |
| `{5CA784EC-8C20-445A-8C9E-7D3F43A08851}` | VLLDP150 | DolbyAPOvlldp150.dll | 0xE |
| `{5F117246-A780-4B6C-B534-661509028E9F}` | AudioMirroring | Dax3Ref.dll | 0xF |

  Le VLLDP hanno in più il bit 0x2 (frame per periodo devono coincidere): **dedotto** dai flag APO standard.
- I CLSID wrapper V1 (`{0EBD8505/8506/8507/8511/8512-…}`) sono solo definiti nelle stringhe, non registrati.
- Effect pack `{F94ABB2E…}` (USB) e `{F94ABB2F…}` (Bluetooth): SFX=wrapper 8605, MFX=8606, offload 8611/8612, modi default/media/movie/communications (+raw per MFX), richiesta di diventare predefinito con priorità 10, contesto `FX\0\{5D36640C-DBC6-4207-A18F-80E0CF46C0AE}\User`. Non riguardano gli altoparlanti interni.

### 1b. `dax3_ext_qc.inf`, classe Extension, ExtensionId `{690A2C79-F293-47D5-BEEA-B59BB258DEA6}`, DriverVer 11/16/2025 10.1117.422.3
- Il nostro dispositivo `AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001` usa la variante **`DeviceExtension_Install_DolbyAccessNoGaming_V2`** (anche IDEA4002, 380717AA, 380317AA, 17AA3801, 380617AA, 380817AA).
- Effetti: `DaxExtFolder=%13%` sulla chiave driver dell'adattatore; copia operator_settings_lenovo_*.json e le tarature `*.xml` (fra cui IDEA4001) nel DriverStore dell'estensione.
- Interfacce `WaveSpeaker`, `TopologySpeaker`, `WaveSpeakerHeadset`, `TopologySpeakerHeadset` (categorie AUDIO, RENDER, REALTIME, TOPOLOGY) → `DolbyAPO_Install_V2`:
  - `EP\0`: `{6CA6A085-3041-482B-9113-C61E7F250356},0 = "0.4.0"` (indicatore "dispositivo Dolby").
  - `FX\0`: associazione KSNODETYPE_ANY; SFX = `{0EBD8605}`, MFX = `{0EBD8606}`, Offload SFX = `{0EBD8611}`, Offload MFX = `{0EBD8612}`; modi SFX: default, media, movie, communications; MFX: gli stessi + raw. **Nessun EFX Dolby** in V2.
- Componenti aggiunti: `SWC\VEN_DOLBY&PID_DAX3APOSVC` (→ 1a) e `SWC\VEN_DOLBY&PID_DAX3HSA_DolbyAccess` (→ 1c).

### 1c. `dax3_swc_hsa_arm64-141226.inf`, classe SoftwareComponent, DriverVer 12/17/2024 3.30803.830.0
- Nessun file, nessun servizio (`AddService=,2`): solo `AddSoftware` tipo 2 = app dello Store. Per `DAX3HSA_DolbyAccess`: `pfn://DolbyLaboratories.DolbyAccess_rz1tebttyb220` (+ codec pack DDP sulle build 26100+). È l'interfaccia utente, non elabora audio.
- Nel DriverStore ci sono due cartelle HSA (`…141226c4e847b734` e `…582fed39a4d5bea4`): quale sia attiva **ignoto** (irrilevante per l'audio).

## 2. Registro reale (**visto**, hive di `/mnt/win`)

### 2a. `HKLM\SOFTWARE\Dolby` (tutto l'albero)
- `DAX`: `DolbyEnable=1`, `LidClose=1`.
- `Fusion`: vuota.
- `Wrapper`: `APO_SFX={E77F483A…}`, `APO_OSFX={E77F483A…}`, `APO_MFX={5CA784EC…}`, `APO_OMFX={5CA784EC…}`, `APO_EFX={5CA784EC…}`.
  Nessun INF scrive questa chiave: la scrive **DAX3API.exe** (**dedotto**: stringhe `SOFTWARE\Dolby\Wrapper`, `DAXAPIImplement::WriteDAXAPORegistryKey`, `SetInnerApoGuid`, `DolbyEndpointControl::GetApoGuid` e l'elenco dei CLSID interni nell'eseguibile).

### 2b. Classi COM
- **Non** in `SOFTWARE\Classes\CLSID`: le registrazioni HKR dell'INF APO sono nella chiave software del componente, `SYSTEM\ControlSet001\Control\Class\{5989fce8-9cd0-467d-8a6a-5419e31529d4}\0007` (DriverDesc "DolbyAPO SWC Device", oem117.inf, 3.30812.891.1), sotto `Classes\CLSID\…` e `AudioEngine\AudioProcessingObjects\…`. Contenuto identico alla tabella 1a; percorsi `%SystemRoot%\System32\DriverStore\FileRepository\dax3_swc_aposvc_arm64.inf_arm64_d496b58e814ffb00\<dll>`.
- Proxy APO Qualcomm: stessa classe, `\0006` (oem92.inf, 1.0.4516.6300): `{697DA8EE-64F9-4096-BEBC-7C1C42CC2876}` "Qualcomm Audio Proxy APO (Endpoint effect)" e `{7B51F67F-7354-481D-8D44-DE3E3818839A}` "(mode effect)", entrambi `qcaudminiport_apo8380.inf_arm64_aa2914460f962a11\ProxyAPO.dll`.
- Altri APO installati ma non sugli altoparlanti: Voice Clarity Microsoft (`\0000`, `\0001`), Qualcomm ASD (`\0002`, `\0003`), Elevoc (`\0004`, `\0005`).
- Chiave driver dell'adattatore `{4d36e96c…}\0003` ("Qualcomm(R) Aqstic(TM) Audio Adapter Device", `AUCD\QCOM0C29`, 1.0.4516.6300): `DaxExtFolder=C:\WINDOWS\System32\DriverStore\FileRepository\dax3_ext_qc.inf_arm64_e5f18b7b3bf0fb11`.

### 2c. Endpoint "Altoparlanti" `MMDevices\Audio\Render\{72a99614-9bc3-4e8f-98a7-30283009ad51}`
- `DeviceState=1` (attivo); unico endpoint di riproduzione. Dispositivo `AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001\5&261EA3AF&0&0`, interfaccia `…\wavespeaker`. `{6CA6A085…},0="0.4.0"` presente.
- `FxProperties` (`{D04E05A6-594B-4FB6-A80D-01AF5EED7D1D},n`):
  - 0 (associazione) = GUID nullo;
  - 5 SFX = `{0EBD8605}`; 6 MFX = `{0EBD8606}`; 7 EFX = `{697DA8EE}` (Qualcomm);
  - 11 Offload SFX = `{0EBD8611}`; 12 Offload MFX = `{0EBD8612}`.
- Modi (`{D3993A3F-99C2-4402-B5EC-A92A0367664B},n`): 5 e 11 = default, media, movie, communications; 6 e 12 = gli stessi + raw.
- Provenienza (`{clsid},100`): i quattro wrapper da `SWD\DRIVERENUM\{690A2C79…}#DOLBYAPO_DAX3APOSVC&6&45857B7&0`, l'EFX da `SWD\DRIVERENUM\PROXYAPO&6&45857B7&0`. Sottochiavi `{08e54ab7…}` e `{45da5c30…}` con `Default/User/Volatile` vuote.

### 2d. Servizi (`SYSTEM\ControlSet001\Services`)
Solo `DolbyDAXAPI`: Type 0x10, Start 2, ErrorControl 1, ObjectName LocalSystem, ImagePath nel DriverStore `…\DAX3API.exe`, Owners `oem117.inf`.

### 2e. Coerenza file
SHA-256 di `DolbyDax3Apo.dll`, `DolbyAPOVR.dll`, `DolbyAPOvlldp150.dll` nel DriverStore = quelli in `$D/bin`; `dax3_ext_qc.inf` del DriverStore = quello in `$D/pkg` (**visto**).

## 3. Ruolo di ogni binario
Tutti: FileVersion/ProductVersion 3.30812.891.0, progetto `c:\DAX38_sign\dax3\…` (**visto**, risorse di versione e percorsi PDB/sorgente).

| Binario | Nome interno | Export | Ruolo |
|---|---|---|---|
| DolbyDax3Apo.dll | DolbyAPOWrapper, "Dolby DAX APO" | COM standard | **Wrapper** registrato sugli endpoint. Legge `SOFTWARE\Dolby\Wrapper\APO_*` e carica l'APO interno. **Visto**: stringa `SOFTWARE\Dolby\Wrapper\` a 0x1800d8b40 usata da `fcn.180039ca8` (0x180039ef4); `APO_SFX`/`APO_MFX` usate da `fcn.180005e3c` e `fcn.18002dc60`; `LoadLibrary` + `GetProcAddress("DllGetClassObject")` in `fcn.18003ae78` (0x18003b2ac, 0x18003b530); log "Load Inner APO (%s) succeed." in `fcn.18002f3f8` (`CLoadInnerApo::LoadAPO`). Contiene i nomi DLL `\DolbyApoVr.dll`, `\DolbyAPOvlldp150.dll` ecc., più `\DolbyAPONs.dll` e `\DolbyAPONs30.dll` (assenti dal pacchetto). Fa da ricampionatore se l'APO interno lavora a un'altra frequenza (`ResamplerHelper`, "Inner APO sample rate"), dialoga con l'interno via `IDolbyApoType::SetType` (SFX/MFX/EFX/offload). Classi anche "CDolbyRecWrapper" e KeywordDetector (cattura). Import: audioeng, ole32 (CoCreateInstance), SHLWAPI. |
| DolbyAPOVR.dll | DolbyApo (PDB DolbyApoVr) | COM | **APO interno "cp" (content processing) attivo in SFX.** Sorgenti `ApoBaseDap2.cpp`, `LibWrapperDap2.cpp`, `LibWrapperVr.cpp`; funzioni `dolby::spatial_sound::dahp::*` (Dolby Atmos for Headphones), `SpatialSound.Native.Configurator.cpp`, effetti `AUDIO_EFFECT_TYPE_VIRTUAL_SURROUND/VIRTUAL_HEADPHONES`, parametri `speaker-virtualizer-enable`, `spatial-enable`, `dap_cpdp_initialized`. Versione della libreria DAP2 interna: **ignoto** (nessuna stringa di versione). |
| DolbyAPOv251.dll | DolbyApo | COM | APO interno DAP v2.5 (`Dap2LibWrapperV2_5`, classi `CDolbyAPO`, `CDolbyAPOgm`). Registrato ma **non usato** qui. |
| DolbyAPOv2100.dll | DolbyApo | COM | APO interno DAP v2.10 (`Dap2LibWrapperV2_10`, stringa "2.10.0"; classi normale e Lite). Registrato ma **non usato** qui. |
| DolbyAPOvlldp150.dll | DolbyApo | COM | **APO interno "vlldp" (device processing) attivo in MFX**, `VlldpLibWrapperV1_5`, `ApoBaseVlldp.cpp`, stato `dap_vlldp_state_s`, include `PPAPIHelper.cpp` di Dax3DapControl. |
| DolbyAPOvlldp.dll, …120, …130, …140 | DolbyApo | COM | Stesse funzioni con librerie VLLDP 1.0/1.2/1.3/1.4 (`VlldpLibWrapperV1_0`, `…V1_4` visti). Non usati qui. |
| Dax3Ref.dll | DaxAudioMirroringDll, "Audio Mirroring APO" | COM | APO di duplicazione audio su più dispositivi; si mette in bypass se non è sull'endpoint predefinito ("APO is not on default audio endpoint. Bypass this APO."). Non sugli altoparlanti. |
| DAX3API.exe | DAXAPI | nessuno | **Servizio `DolbyDAXAPI`** (LocalSystem). Server RPC (`DaxRpcEndpoint`, `DAXRPC.cpp`), legge `DaxExtFolder`, sceglie e analizza il file di taratura (`TuningFileParser`, `UnifiedTuningManager`, regex `…(Default)…\.xml`), gestisce operator settings, profili, `DolbyEnable`, `LidClose`, Fusion, scrive `SOFTWARE\Dolby\Wrapper` (**dedotto**, 2a). Importa `Dax3DapControl.dll` e `DAXSSID.dll`. Stringhe: "DAX content processing APO exist", "DAX device processing APO exist", "Enable AO&AR in content processing APO because device processing APO does not exist", `DLLs\ARM64\DolbyHrtfEnc.dll`. |
| Dax3DapControl.dll | Dax3DapControl | `OpenDapControl`, `CloseDapControl`, `GetDapParam`, `SetDapParam`, `SetDapVariantParam` | Libreria di controllo con cui il servizio imposta i parametri negli APO in esecuzione (dentro audiodg). Legge anch'essa `SOFTWARE\Dolby\Wrapper\APO_*`, enumera endpoint e fattore di forma (`dap_cpdp-endpoint-form-facotr`). Canale verso gli APO: memoria condivisa (`SharedMemoryController.cpp` è negli APO) — **dedotto**. |
| DAXSSID.dll | DaxSSID | `GetSSID`, `ClearSSID`, `GetPciHardwareId`, `GetSystemHardwareId`, `GetSystemDeviceInstanceId`, `IsSupportedUsbDevice` | Ricava l'ID hardware/SSID del sistema (SETUPAPI, CFGMGR32) per scegliere la taratura giusta (es. `…SUBSYS_IDEA4001…xml`) — **dedotto**. |
| CaptureStreamMonitor.dll | CaptureStreamMonitor | `StartMonitor` | Caricato da DAX3API; osserva flussi di cattura/VoIP e cambi di endpoint predefinito, imposta il profilo ("Set profile to [%s] on endpoint …"), client RPC `ncalrpc`/`DaxRpcEndpoint`. Non elabora audio. |

## 4. Catena effettiva sugli altoparlanti interni

```
app → audiodg (motore audio)
  SFX per flusso  : {0EBD8605} DolbyDax3Apo.dll ──Wrapper\APO_SFX──► {E77F483A} DolbyAPOVR.dll   ("cp": DAP2 + virtualizzatore)
  [mixer]
  MFX per modo    : {0EBD8606} DolbyDax3Apo.dll ──Wrapper\APO_MFX──► {5CA784EC} DolbyAPOvlldp150.dll ("vlldp" v1.5)
  EFX endpoint    : {697DA8EE} ProxyAPO.dll (Qualcomm, non Dolby)
  → driver Qualcomm → ADSP (catena DSP del documento REVERSE-AUDIO-WINDOWS.md 5b) → WSA884x
(in offload: {0EBD8611}/{0EBD8612} → stessi due APO interni)
controllo: DolbyAccess (app Store) ⇄ RPC ⇄ DAX3API.exe (servizio) → Dax3DapControl → parametri negli APO
           DAX3API legge la taratura IDEA4001 (tuning-cp → VR, tuning-vlldp → VLLDP150) scelta con DAXSSID
```
- **Visto**: tutti i collegamenti CLSID → DLL e endpoint → CLSID (sezioni 1–2); il wrapper legge `Wrapper\APO_*` e carica una DLL tramite `DllGetClassObject` (sezione 3).
- **Dedotto**: l'ordine di elaborazione SFX → MFX → EFX è quello standard di Windows; quale percorso (normale o offload) sia usato in pratica dipende dal driver: **ignoto**, ma i due percorsi caricano gli stessi APO interni.
- **Dedotto**: l'elaborazione "Dolby" che si sente è divisa in due: il VR fa la parte sui contenuti (virtualizzatore surround, enfasi dialoghi, livellatore, IEQ), il VLLDP150 la parte legata al dispositivo (ottimizzatore audio e regolatore multibanda, "AO&AR"), che passerebbe al VR solo se il VLLDP mancasse. Coerente con la struttura `tuning-cp`/`tuning-vlldp` della taratura e con il progetto gemello SP11X1e-audio, che indica `DolbyAPOvlldp150.dll` come "live dynamic processor" (stessi nomi, build diversa: dimensioni dei file diverse).

## 5. Ignoti
- Versione della libreria DAP2 dentro `DolbyAPOVR.dll`.
- Ripartizione esatta degli algoritmi fra VR e VLLDP150 (serve leggere `LibWrapperDap2`/`LibWrapperVlldp` e la taratura).
- Se il motore audio usa il percorso offload (`8611/8612`) o quello normale.
- Che cosa fa `ProxyAPO.dll` (EFX Qualcomm) nell'elaborazione.
- Formato e canale esatti fra Dax3DapControl e APO (memoria condivisa: nome, struttura).
- Il ruolo di `security-key` nella sezione `<setting>` della taratura (lega il file all'ID hardware `AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001`); qui non analizzato.
- I CLSID `{D9916F9D…}` e `{D9916F9F…}` presenti in DAX3API ma non registrati: funzione ignota (forse NS).

## 6. Passo successivo consigliato
Studiare l'interfaccia del wrapper verso gli APO interni (`IDolbyApoType`, `LockForProcess`, formato richiesto, frequenza di campionamento) e i due "LibWrapper" (`LibWrapperDap2` in VR, `VlldpLibWrapperV1_5` in VLLDP150): quali parametri della taratura ricevono e in che formato. È il contratto minimo che un ospite Linux dovrebbe riprodurre per far girare le stesse due DLL; confrontarlo con `dolby-port/` del progetto gemello, che ha già un caricatore PE per `DolbyAPOvlldp150.dll`.

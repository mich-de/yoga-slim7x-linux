# 04 - Servizio DAX3API.exe e DLL di controllo

Fase di studio, solo lettura statica (stringhe, import/export, tabelle nei binari, registro e file del Windows montato). Nessuna esecuzione. Le osservazioni dal vivo citate vengono dal progetto gemello SP11 (Surface Pro 11, stesso DAX3 su Snapdragon, build 3.30704) e sono segnate come tali.

Legenda: **visto** = trovato in un file o binario (con riferimento); **dedotto** = ragionamento su elementi visti; **ignoto** = non determinato.

Abbreviazioni:
- D = scratchpad/dolby (binari in D/bin, dump in D/dis, pacchetti in D/pkg)
- EP = endpoint altoparlanti `{0.0.0.00000000}.{72a99614-9bc3-4e8f-98a7-30283009ad51}`
- MMD = `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{72a99614-...}`

## Sintesi

1. DAX3API.exe è un servizio di politica e configurazione, non sta nel percorso dell'audio. Gira come LocalSystem e fa quattro cose:
   - legge la taratura XML e le impostazioni JSON;
   - calcola i valori dei parametri per il profilo attivo;
   - li scrive come proprietà dell'endpoint audio;
   - dice al wrapper quale APO interno caricare.
2. Gli APO (DolbyDax3Apo e gli APO interni) non parlano mai con il servizio via RPC. Leggono:
   - il registro `HKLM\SOFTWARE\Dolby\Wrapper`;
   - l'archivio proprietà dell'endpoint (IMMDevice::OpenPropertyStore), che poi seguono con IMMNotificationClient::OnPropertyValueChanged.
3. La memoria condivisa serve solo a funzioni accessorie: visualizzatore, eyes tracking, audio sharing, canale di sessione verso DAPVR.
4. Di conseguenza l'elaborazione può girare senza servizio, se l'ambiente fornisce:
   - (a) la scelta dell'APO interno;
   - (b) un IPropertyStore con le chiavi Dolby già valorizzate;
   - (c) le chiavi standard dell'endpoint (fattore di forma, Disable_SysFx, ...).

   Su questo portatile i valori correnti sono già salvati nel registro di Windows (MMD\Properties) e si possono riusare come istantanea. Il cambio di profilo dal vivo richiede invece di ricalcolare i valori, cioè di sostituire la logica del servizio.

## 1. Registrazione, avvio, file letti, stato salvato

### Registrazione
- **visto** (D/pkg/dax3_swc_aposvc_arm64.inf, sezione DolbyAPO_ServiceInstall):
  - servizio `DolbyDAXAPI`, ServiceType 0x10 (processo proprio), StartType 2 (automatico), ErrorControl 1;
  - binario `%13%\DAX3API.exe`;
  - installato come componente software `SWC\VEN_DOLBY&PID_DAX3APOSVC`, aggiunto dall'INF di estensione Qualcomm con `AddComponent = DolbyAPO_DAX3APOSVC` (dax3_ext_qc.inf).
- **visto** (hive SYSTEM, ControlSet001\Services\DolbyDAXAPI):
  - ImagePath = `%SystemRoot%\System32\DriverStore\FileRepository\dax3_swc_aposvc_arm64.inf_arm64_d496b58e814ffb00\DAX3API.exe`;
  - ObjectName = LocalSystem;
  - nessun argomento nell'ImagePath.
- **visto**, stringhe di WinMain (DAX3API.exe.str16 righe 686-702): opzioni della riga di comando `install`, `service`, `remove`, `unregserver`, `capturestream`, `spatialsound`. In modalità `capturestream` carica `CaptureStreamMonitor.dll` ("Load CaptureStreamMonitor.dll failed!").
- **visto**: import di StartServiceCtrlDispatcherW, RegisterServiceCtrlHandlerExW, CreateServiceW, DeleteService; classi `CServiceBase` e `CDAXService` (OnStart, OnStop, OnSessionChanged).
- **visto**: il servizio lancia processi figli nella sessione utente:
  - stringhe `"%s\%s" -capturestream` e ` -spatialsound `;
  - import CreateProcessAsUserW;
  - per prendere il token cerca `winlogon.exe` nella sessione attiva.
- **visto dal vivo** (gemello, 2026-08-04-DOLBY-LIVE-KDNET-HOT-PATH.md): due processi DAX3API.exe. Il padre carica Dax3DapControl.dll; il figlio carica Dax3DapControl.dll e CaptureStreamMonitor.dll; Dax3Ref.dll non è caricato.

### Sequenza di avvio (dedotta dall'ordine delle stringhe e dai nomi delle funzioni)
1. Ricava l'ID di sistema tramite DAXSSID.dll (`getSystemId`, con ciclo "Cannot queried system ID. Sleep %dms and retry").
2. Trova la cartella dell'estensione:
   - **visto**: valore `DaxExtFolder` scritto dall'INF di estensione (`HKR,,DaxExtFolder,,%13%`) nella chiave driver `SYSTEM\CurrentControlSet\Control\Class\{4d36e96c-...}\0003`;
   - **visto** nell'hive: `C:\WINDOWS\System32\DriverStore\FileRepository\dax3_ext_qc.inf_arm64_e5f18b7b3bf0fb11`;
   - **visto**: la chiave driver si risolve con `DEVPKEY_Device_Driver` (stringa "Got DEVPKEY_Device_Driver = %s").
3. Cerca la taratura con questi elementi (**visto**):
   - "Ready to search tuning file in folder", "Tuning file name: %s";
   - regex `Speaker_(?:`, `Headphone_(?:`, `|Default)[\S\s]*(\.xml)`;
   - riprova se manca ("NO Tuning File Found! Sleep %dms and retry").

   Il nome del file è l'ID di sistema: `AUCD_DEV_0C29_SUBSYS_IDEA4001_ADCM_SUBSYS_IDEA4001.xml`, presente nella cartella DriverStore (**visto**).
4. Legge le impostazioni JSON:
   - **visto**: la taratura contiene `<settings_filename value="operator_settings_lenovo_default.json"/>`;
   - **visto**: `JsonSettingsManager` gestisce le catene `import_settings` e ripiega su XML ("JSON settings is empty. Attempt to load XML settings.");
   - **visto**: `default_settings.json` e `Default_settings.xml` stanno nella cartella del pacchetto servizio.
5. Enumera gli endpoint di rendering (IMMDeviceEnumerator) e per ciascun endpoint DAX crea un `DolbyEndpointControl` con i relativi TuningManager. **visto**: "CreateDolbyEndpointControllers", "CreateTuningManagers", "IsDaxEndpoint".
   - Marcatore di endpoint Dolby, **visto**: l'INF di estensione scrive in `EP\0` la chiave `{6CA6A085-3041-482B-9113-C61E7F250356},0 = "0.4.0"`, presente in MMD\Properties.
6. Scrive `HKLM\SOFTWARE\Dolby\Wrapper` con il CLSID dell'APO interno per ogni slot (sotto).
   - **visto**: "WriteDAXAPORegistryKey", "SetInnerApoGuid", ciclo "No active DAX speaker! Sleep and retry".
7. Applica la taratura (**visto**: "ApplyTuningData") e scrive i parametri sull'endpoint tramite Dax3DapControl (sezione 3).
8. Avvia il server RPC (sezione 2) e registra le notifiche:
   - dispositivo predefinito ("Cannot monitor default device change event! DAX API cannot run properly!");
   - volume (IAudioEndpointVolume);
   - cambio di sessione utente.

### Stato persistente trovato sul disco Windows (visto)
- `HKLM\SOFTWARE\Dolby\Wrapper`:
  - APO_MFX, APO_EFX, APO_OMFX = `{5CA784EC-8C20-445A-8C9E-7D3F43A08851}` (VLLDP150);
  - APO_SFX, APO_OSFX = `{E77F483A-E3A7-4647-B3AB-51FD990F55BA}` (DAPVR).
- `HKLM\SOFTWARE\Dolby\DAX`: DolbyEnable=1, LidClose=1. `HKLM\SOFTWARE\Dolby\Fusion` è vuota.
- `SYSTEM\...\Class\{4d36e96c-...}\0003\Settings`: DolbySlidingBass=0. Lo scrive DAX3API (stringa "RegSetValueEx for DolbySlidingBass failed").
- `C:\ProgramData\Dolby\DAX3\Runtime.xml`:
  - 175 byte, contiene solo `VisualizerEnabled=false`;
  - lo gestisce `RuntimeConfigController`, che sa salvare anche DolbyEnabled, ProfileList e SelectedPeripheral (stringhe viste);
  - qui oggi quei campi non ci sono.
- MMD\Properties: le famiglie di chiavi Dolby con i valori dei parametri (sezione 3). È lo stato effettivo usato dagli APO.
- MMD\FxProperties:
  - CLSID dei wrapper V2: SFX `{0EBD8605-...}`, MFX `{0EBD8606-...}`, OSFX `{0EBD8611-...}`, OMFX `{0EBD8612-...}`;
  - EFX = `{697DA8EE-...}` (PROXYAPO di sistema);
  - sottochiave di contesto `{45da5c30-2837-4ac4-b1e2-50acc3865974}\User` con le chiavi DAHP `{1b4dab55-...},1/2/4/5` e altre due (`{e36464a1-...},1`, `{d5e60007-...},2`).
- Nessuna chiave Dolby nell'NTUSER.DAT dell'utente.
- Nessuna app Dolby Access o Dolby Settings installata per l'utente. In Packages c'è solo DolbyDigitalPlusDecoderOEM. **Dedotto**: oggi nessuna interfaccia utente pilota il servizio, quindi il profilo attivo è quello predefinito dalle impostazioni JSON e dalla taratura.

## 2. Interfacce esposte

### RPC
- **visto**, stringhe in DAX3API: `ncalrpc`, `DaxRpcEndpoint`, "DAX RPC Server". Import di RpcServerUseProtseqEpW, RpcServerRegisterIf3, RpcEpRegisterW, RpcServerListen.
- **visto**: struttura RPC_SERVER_INTERFACE a offset file 0x1f0880 (VA 0x1401f2280).
  - UUID dell'interfaccia: `11c6212d-d5f3-4500-ab16-634dc63037be`, versione 1.0, sintassi NDR;
  - tabella di dispatch con 99 procedure;
  - script: D/work/04/rpcif.py e rpcdisp.py.
- **visto**: metodi `RpcServer::DAXRPC::*`, tra cui:
  - SetDolbyEnable, SetActiveProfile;
  - Set...Enable / Set...Value per SurroundVirtualizer, DialogEnhancer, VolumeLeveler, BassEnhancer;
  - Get/SetGEQLevels, Get/Set/Reset IEQ, Get/Set/Reset ActiveSubProfile e SubProfileDirty;
  - radar e visualizzatore (Get/Set di Enable, Size, Position, Skin, ...);
  - AutoSwitch, CaptureStreamDetectedEnabled, Hotkey;
  - GetCaptureStreamApplications, GetAutoProfileApplicationGroup, GetPeripheralData;
  - WaitForEventCallback, cioè callback in attesa lunga: OnPropertyChanged, OnGEQLevelsChanged, OnEndpointMasterVolumeLevelChanged, OnAutoProfileListChanged, ...
- **visto**: accesso generico a proprietà per nome (`DAXAPIImplement::Get/SetProperty(Ex)`, "Client [%d] attempt to set property value: name - [%s]"). Nomi visti:
  - operator, default_profile, endpoint_guid, all_endpoint_guid, endpoint_properties, default_endpoint;
  - form_factor, is_dax_endpoint, master_volume;
  - ns_enable, ns_mode, fusion_enable;
  - audio_mirroring_*, bt_sharing_*, capture_only, voip_enabled_renders, ...
- Client:
  - **visto**: CaptureStreamMonitor.dll importa solo le funzioni RPC lato client (RpcStringBindingComposeW, RpcBindingFromStringBindingW), contiene lo stesso UUID e le stringhe `DaxRpcClient` + `ncalrpc` + `DaxRpcEndpoint`;
  - **visto**: stringhe in DAX3API `DolbyLaboratories.DolbyAccess_` e `DolbyLaboratories.DolbySettings_rz1tebttyb220`;
  - **dedotto**: le app UWP Dolby sono i client principali;
  - **dedotto**: DAX3API controlla la firma Authenticode del processo client (import CRYPT32 CryptQueryObject/CertFindCertificateInStore/CertGetNameStringW); flusso non verificato;
  - **visto**: nessun APO contiene l'UUID RPC né importa RPCRT4.

### COM e AppService
- **visto**: script di registrazione ATL dentro DAX3API, `DolbyDAX Class` CLSID `{20532D01-15BE-4BB9-A727-CA34555D881C}`, TypeLib `{3A1C2709-...}`. Nell'hive SOFTWARE non è registrato. **Dedotto**: residuo, non usato.
- **visto**: classe `SpatialSoundAppService` e stringa "Connect to AppService failed" (WinRT AppServiceConnection). **Dedotto**: è la modalità `-spatialsound` verso l'app Dolby.

### Pipe
- **visto**: nessun nome di named pipe. "broken pipe" è solo testo della libreria standard C++.

### Memoria condivisa ed eventi
- **visto**: `SharedMemorySessionManager2` in DAX3API e `SharedMemorySessionClient2` in DolbyAPOVR.dll (schema di nomi `%sMAPPING-FILE-MUTEX-%s`, `%sMAPPING-FILE-EVENT-%s`, prefisso `Global\`).
- **visto**: evento `Global\CaptureStream-Event-{52BA4EBB-32F8-42C6-8D17-438D197ECD23}-` per CaptureStreamMonitor.
- Funzioni accessorie, **visto**:
  - DolbyAPOvlldp150: "Init shared memory failed. Visualizer will be disabled.";
  - DolbyAPOVR: "Init eyes tracking shared memory failed. Eyes tracking will be disabled.", "Init shared memory for audio sharing failed.".
- **Dedotto**: canale opzionale. Se fallisce, l'APO disabilita solo la funzione accessoria.

## 3. Come i parametri arrivano all'elaborazione

### Catena (visto nei nomi, dedotto nell'ordine)
1. RPC SetActiveProfile, o avvio del servizio.
2. `DAXAPIImplement` → `DolbyEndpointControl` → TuningManager: profilo + IEQ + GEQ + dispositivo dalla taratura XML.
3. `DAPControl::Update` → export di Dax3DapControl.dll: `OpenDapControl`, `SetDapParam`, `SetDapVariantParam`, `GetDapParam`, `CloseDapControl`.
4. `ApoController::SetParameter` → IMMDevice::OpenPropertyStore(STGM_READWRITE, con ripiego in sola lettura) → IPropertyStore::SetValue sull'endpoint.
   - Stringhe viste in Dax3DapControl: "Failed to open property store in read write mode, try read only mode again", "Set property key [%s, %s, %d]".
5. Windows salva i valori in MMD\Properties e notifica i client.
6. L'APO interno riceve `IMMNotificationClient::OnPropertyValueChanged` ("Changed device property: {...}#%d", `CApoBase::OnPropertyValueChanged` in DolbyAPOvlldp150), rilegge con `UpdatePropertyKeys` e passa i valori alla libreria (`VlldpLibWrapperV1_5::UpdatePropertyKeys`).

- **visto dal vivo** (gemello): `SetDapVariantParam(x0 = stringa ID endpoint "{0.0.0.00000000}.{guid}", x1 = id parametro, es. 0x838, x2 = valore variante, x3 = 1)`, chiamata da DAX3API anche senza azioni dell'utente.

### Formato
- Ogni parametro è una PROPVARIANT in una PROPERTYKEY {fmtid, pid}.
- **visto**: tabella in Dax3DapControl.dll a offset file 0x5cff8, voci da 24 byte (GUID + pid + 4 byte a zero). Elenco completo in D/work/04/dapcontrol_pkeys.txt.
  - famiglia DAP `{f112024a-fe30-42a8-80ab-8dd825a06f78}`: 72 pid tra 0 e 78;
  - famiglia `{0c5e4949-7a67-4b9e-9069-1d6259682436}`: pid 3201, 3203, 3010, 3011;
  - famiglia VLLDP `{5510c7ab-dfc2-40d0-a98b-5f77f697005e}`: pid 0-41;
  - `{dc827e12-807b-4fbb-8e3c-6c62981dd3c9}`: pid 0-1;
  - `{5b5e03cb-8070-420d-b794-8a28c89f6274}`: pid 0-1;
  - `{f19f064d-082c-4e27-bc73-6882a1bb8e4c}`: pid 0.
- **visto**: le stesse GUID compaiono, con lo stesso numero di occorrenze, in tutti gli APO interni, in DAX3API, in CaptureStreamMonitor e in DAXSSID. **Dedotto**: tabella comune di una libreria condivisa (dax_utils).
- Nomi dei parametri, **visto** in Dax3DapControl.str16: `dap_*` (circa 67 nomi nel blocco contiguo), `vlldp_*` (circa 36-40), `ns_bypass`, `ns_mode`.
  - **dedotto**: il blocco VLLDP (40 nomi più i 2 ns) corrisponde ai 42 pid della famiglia 5510c7ab;
  - **ignoto**: la corrispondenza esatta nome → pid. L'ordine delle stringhe non coincide con il numero di voci DAP (67 contro 76). Va ricavata da ConvertParameterToPropVariant.
- Tipi nel registro, **visto** in MMD\Properties:
  - la maggior parte VT_I4 (prefisso 0x03), ad esempio f112024a,2 = 96 e f112024a,6 = -320;
  - vettori e blob (prefisso 0x41 = VT_BLOB), ad esempio 5510c7ab,7/8/9/17/22/31 e f112024a,13/18/21/22/55 (bande IEQ/GEQ/ottimizzatore, soglie del regolatore);
  - **visto**: Dax3DapControl importa InitPropVariantFromInt32Vector. **Dedotto**: i vettori di interi sono serializzati come blob.
- Selezione dell'APO per il nome di libreria, **visto** in Dax3DapControl:
  - dap2.5 → {d9916fa0-...}, dap2.5-gaming → {d9916f9f-...};
  - dap2.10 → {efc7a7b3-...}, dap2.10-lite → {1bedaecc-...};
  - DAPVR → {e77f483a-...};
  - vlldp1.0 → {d9916f9e-...}, vlldp1.2 → {d9916f9c-...}, vlldp1.3 → {6e4dd785-...}, vlldp1.4 → {97acd2ab-...}, vlldp1.5 → {5ca784ec-...};
  - vlldp1.6 → {a03dd626-d30f-47ed-bdad-70cbb1233749}, non presente nel pacchetto.
- Canale ASAR/DAHP, separato e non usato dagli APO di questo pacchetto:
  - **visto**: DAX3API contiene IAudioSystemEffectsPropertyStore, la GUID di contesto `{45da5c30-...}` e 5 occorrenze della famiglia DAHP `{1b4dab55-...}`;
  - **visto**: queste chiavi sono nell'archivio User di FxProperties;
  - **visto** (gemello, 2026-08-09-ASAR-DAX-LIFECYCLE...): le consuma DolbyAudioProcessing.dll dell'app Dolby (Spatial Sound), con pid 4 = blob di inizializzazione e pid 5 = blob di runtime, insieme a un canale a memoria condivisa (messaggio `8,0,2,0,size,payload`);
  - **dedotto**: non riguarda VLLDP150 o DAPVR del pacchetto DAX3.

## 4. Ruolo delle DLL di controllo

| DLL | Export (visto) | Chi la carica | Ruolo |
|---|---|---|---|
| Dax3DapControl.dll | OpenDapControl, CloseDapControl, SetDapParam, SetDapVariantParam, GetDapParam | DAX3API.exe (import statico, visto), padre e figlio (visto dal vivo nel gemello) | Traduce id parametro → PROPERTYKEY e scrive o legge l'archivio proprietà dell'endpoint. Non è usata dagli APO. |
| DAXSSID.dll | GetSSID, ClearSSID, GetSystemHardwareId, GetSystemDeviceInstanceId, GetPciHardwareId, IsSupportedUsbDevice | DAX3API.exe (import statico, visto) | Legge gli ID hardware (CM_Locate_DevNodeW, CM_Get_Parent, CM_Get_DevNode_Property) e costruisce l'ID di sistema `ENUM_DEV_xxxx_SUBSYS_xxxx...`, usato come nome del file di taratura (regex per INTELAUDIO, SDW, SST, USB VID/PID visti). |
| CaptureStreamMonitor.dll | StartMonitor | DAX3API.exe nel figlio `-capturestream` (stringa vista, caricamento dinamico) | Client RPC del servizio. Segue le sessioni audio (IAudioSessionControl2) e ricava il profilo automatico per applicazione (LoadAutoProfileSettings) e lo stato capture_only/VoIP, che scrive come proprietà via RPC. |
| Dax3Ref.dll | DllCanUnloadNow, DllGetClassObject, DllRegisterServer, DllUnregisterServer | Server COM in-process. Registrazione INF `AudioMirroring_AddReg` (CLSID `{5F117246-A780-4B6C-B534-661509028E9F}`, visto); nell'hive SOFTWARE non c'è | È l'APO "AudioMirroring" (pdb `...\AudioMirroring\...\Dax3Ref.pdb`, classe AudioMirroringImpl, visto). Non serve per gli altoparlanti; non caricato nel gemello. |

## 5. Lato elaborazione senza servizio

- Wrapper (DolbyDax3Apo.dll):
  - **visto**: legge `SOFTWARE\Dolby\Wrapper\` (valori APO_SFX/MFX/EFX/OSFX/OMFX/KD*, più `DumpAudio`) in `CDolbyAPOWrapperChain::QuerySettings`, poi carica la DLL interna tra quelle elencate (`\DolbyAPOvlldp150.dll`, `\DolbyApoVr.dll`, ...);
  - **visto**: in caso di errore "Create APO instance failed, Working in bypass mode.";
  - **dedotto**: se la chiave Wrapper non esiste, il wrapper lascia passare l'audio senza elaborarlo. Il servizio serve almeno una volta per creare la chiave, che però resta salvata nel registro.
- APO interno (VLLDP150, DAPVR):
  - **visto**: apre da solo l'archivio dell'endpoint ("OpenPropertyStore failed") e legge PKEY_AudioEndpoint_FormFactor, PKEY_DAX2_FormFactorOverride e PKEY_AudioEndpoint_Disable_SysFx ("Dolby APO is bypassed", "VLLDP APO bypassed!", "DAP VLLDP bypass flag");
  - **visto**: se una chiave manca registra "Failed to get value of property key %s." (DolbyAPOvlldp150, riferimenti a 0x1800fda38 e 0x1800fda94). Nel tratto letto è solo un messaggio di log, senza ritorno di errore;
  - **dedotto**: l'APO continua con il valore che aveva già o con il predefinito interno della libreria;
  - **ignoto**: quali siano i predefiniti interni.
- **visto**: "APOInitSystemEffects: DSP module detected - bypass mode" e "Dolby PP module not found - legacy mode: processing audio". Dipende dal driver audio (IKsControl e topologia), non dal servizio.
- Memoria condivisa assente: si disattivano solo visualizzatore, eyes tracking e audio sharing (visto).
- Conclusione (**dedotto**): con il registro già popolato da Windows, l'elaborazione funziona senza servizio con l'ultimo profilo applicato, ma senza cambi di profilo, profilo automatico o reazione a volume e postura. Il servizio non è nel percorso dei campioni.

## 6. Profili e funzioni noti al servizio

- Profili nella taratura del portatile (visto, `<profile type=...>`):
  - dynamic, movie, music, game, voice, voice_onlinecourse, personalize_user1/2/3, off;
  - nel JSON compaiono con l'iniziale maiuscola (Dynamic, Music, Movie, Voice);
  - sottoprofili e preset di gioco in DAX3API (visto): shooter, racing, onlinecourse, personalize, dynamic, default.
- Preset IEQ (visto): ieq_off, ieq_detailed, ieq_balanced, ieq_warm (curve a 20 bande nella taratura).
- SKU e modalità (visto): Gaming, Mainstream, DolbyAudio, DolbyAudioPremium, DolbyAtmosSpeakerSystem, DolbyAudioSpeakerSystem, DolbyAtmosSpeakerSystemForGaming. Questa taratura ha `sku=DolbyAtmos`.
- Funzioni esposte via RPC (visto):
  - Dolby on/off;
  - virtualizzatore surround (enable/value);
  - dialog enhancer (enable/value);
  - volume leveler (enable/value);
  - bass enhancer;
  - GEQ (livelli), IEQ;
  - radar sonoro e visualizzatore;
  - profilo automatico per applicazione;
  - rilevamento dei flussi di cattura;
  - riduzione del rumore in downlink (ns_enable/ns_mode);
  - audio mirroring, BT sharing.
- Parametri DAP e VLLDP: elenco completo dei nomi in Dax3DapControl (sezione 3). Tra questi:
  - bass enhancer, bass extraction, dialog enhancer, GEQ, IEQ;
  - regulator, surround decoder, surround/height virtualizer, volume leveler e modeler;
  - per VLLDP: sliding bass, compressore multibanda, noise gate, peak level, guadagni e mute per canale.
- Stato di postura e fattore di forma (visto): laptop, tablet, lay_flat, lid_close, detachable_speaker, hybridaudio_detached e simili. Lo sostituiscono override di terze parti (Realtek, Everest, CMedia, Cirrus DBE) e chiavi Lenovo (`SOFTWARE\Lenovo\MoccaMode`, `IBMPMSVC\Transform`).

## Ignoto / non analizzato

- Corrispondenza esatta nome parametro ↔ pid e unità e scale di ogni valore.
- Il significato delle famiglie 0c5e4949, dc827e12, 5b5e03cb e f19f064d (blob di formato?).
- La taratura contiene `<security-key value="AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001=...">`, letta da DAX3API (stringa `security-key` vista).
  - Come e dove viene verificata non è stato analizzato, per scelta: è un controllo di autenticità e non va aggirato;
  - per l'uso su questo stesso portatile si riusano i valori che Windows ha già prodotto.
- Che cosa decide quale profilo è attivo dopo un riavvio senza app (dedotto: default_profile dal JSON).
- Il flusso esatto di controllo della firma del client RPC.

## Passo successivo consigliato

1. Esportare in sola lettura da MMD\Properties le famiglie Dolby (f112024a, 5510c7ab, 0c5e4949, dc827e12, 5b5e03cb, f19f064d, 6ca6a085) e da `SOFTWARE\Dolby\Wrapper`, in un file di testo (PROPERTYKEY → tipo → byte). Sarà l'istantanea della configurazione per l'ospite Linux.
2. Su Linux far leggere all'APO interno (VLLDP150 per MFX, DAPVR per SFX) un IPropertyStore finto alimentato da quell'istantanea, più FormFactor, Disable_SysFx=0 e il marcatore 6ca6a085. Niente servizio né RPC.
3. Solo dopo, se servono più profili: ottenere un'istantanea per profilo invece di reimplementare il calcolo della taratura. Oggi in Windows manca un'app per cambiare profilo, quindi prima va installata l'app Dolby prevista dal pacchetto HSA; poi si cambia profilo e si riesporta il registro.

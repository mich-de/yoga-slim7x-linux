# 02 - Interfaccia COM e ciclo di vita dell'APO Dolby (DAX3, ARM64)

Fonte: lettura statica dei binari in `scratchpad/dolby/bin` (pacchetto dax3_swc_aposvc), registro di Windows in sola lettura, INF del pacchetto.
Nessuna esecuzione. Etichette: **visto** = file e indirizzo o stringa; **dedotto** = ragionamento su dati visti; **ignoto** = non determinato.
Indirizzi = VA con ImageBase 0x180000000 (tutti i DLL). File di lavoro (script e disassemblati mancanti): `scratchpad/dolby/work/02`.
Nota: DolbyDax3Apo.dll e DolbyAPOVR.dll non avevano disassemblato in `dis/`; generato in `work/02`.

## 1. Quale DLL contiene l'APO vero

Catena per gli altoparlanti (endpoint `{72a99614-...}`):

- FxProperties dell'endpoint: SFX = `{0EBD8605-...}`, MFX = `{0EBD8606-...}`, offload `...8611`/`...8612`, EFX = ProxyAPO Qualcomm `{697DA8EE-...}` (**visto**, registro).
- INF: i CLSID `0EBD86xx` hanno InProcServer32 = `%13%\DolbyDax3Apo.dll` (cartella DriverStore), registrati con `HKR` e non in `HKLM\SOFTWARE\Classes` globale (**visto**: dax3_swc_aposvc_arm64.inf righe 97-123; assenti in `Classes\CLSID` e `Classes\AudioEngine\AudioProcessingObjects` del hive).
- `HKLM\SOFTWARE\Dolby\Wrapper`: `APO_SFX`/`APO_OSFX` = `{E77F483A-E3A7-4647-B3AB-51FD990F55BA}`, `APO_MFX`/`APO_OMFX`/`APO_EFX` = `{5CA784EC-8C20-445A-8C9E-7D3F43A08851}` (**visto**). Il wrapper legge questa chiave (stringhe `SOFTWARE\Dolby\Wrapper\`, `DumpAudio`, `APO_SFX`... in DolbyDax3Apo.dll; **visto**).
- Tabella CLSID -> nome DLL nel wrapper, costruita a 0x180004548..0x1800047b8 (coppie GUID 16 byte + stringa UTF-16) (**visto**):
  - `E77F483A` (0x1800cbcf0) -> `\DolbyApoVr.dll` (0x1800ce018)
  - `5CA784EC` (0x1800cbd50) -> `\DolbyAPOvlldp150.dll` (0x1800ce0f0)
  - altri: NS, NS30 (`9B5F8668`), v251, v2100, vlldp, vlldp120/130/140.
- I CLSID E77F483A e 5CA784EC compaiono in binario solo in DolbyAPOVR.dll (0x1801a6480, 0x1801a6ab8) e DolbyAPOvlldp150.dll (0x1801031a0, 0x180103200) oltre al wrapper (**visto**). Le risorse REGISTRY confermano: `{5CA784EC-...} = 'DolbyAPOVlldp150 Class'` (**visto**, stringa).
- Conclusione: per gli altoparlanti lavorano **due** APO interni, in serie: SFX = **DolbyAPOVR.dll** (classe `CDolbyAPO`, base `CApoBaseDap2`, libreria `LibWrapperVr`/`LibWrapperDap2`) e MFX = **DolbyAPOvlldp150.dll** (classe `CDolbyAPOVlldp150`, base `CApoBaseVlldp`, libreria `VlldpLibWrapperV1_5`) (**visto** RTTI). Ordine dei campioni VR -> VLLDP (**dedotto**: SFX precede MFX nel grafo di Windows; coerente con il progetto gemello, docs/findings/2026-08-09-ASAR-ORACLE-VR-BUFFER-PROVENANCE.md).
- Il wrapper DolbyDax3Apo.dll è un proxy: classi `CDolbyAPOWrapper` SFX/MFX/EFX/Offload e `CDolbyRecWrapper` (**visto**, stringhe).

Il resto del rapporto analizza in dettaglio DolbyAPOvlldp150.dll; DolbyAPOVR.dll ha la stessa base `CApoBase` e le stesse strutture (verificato punto per punto sotto).

## 2. Caricamento, class factory, vtable, QueryInterface

### 2.1 Come il wrapper carica l'APO interno (CLoadInnerApo::LoadAPO, funzione 0x18003ae10 in DolbyDax3Apo.dll)
- `LoadLibraryW(percorso)` (IAT 0x1800c81c8, chiamata a 0x18003b130) (**visto**). Percorso = cartella + nome dalla tabella; la cartella è quella del wrapper (DriverStore) (**dedotto**, non verificato il punto in cui si compone; **ignoto** esatto).
- `GetProcAddress(h, "DllGetClassObject")` (0x18003b2a8..0x18003b2bc) (**visto**).
- `DllGetClassObject(CLSID interno, IID_IClassFactory, &cf)` (0x18003b2c8..0x18003b2e8, IID a 0x1800e1338) (**visto**).
- `cf->CreateInstance(NULL, IID_IAudioProcessingObject, &apo)` (0x18003b3a0..0x18003b3c8; IID a 0x18012d138 = FD7F2B29) (**visto**). Nessuna aggregazione.
- Errori registrati: "LoadLibrary failed", "DllGetClassObject failed", "CreateInstance failed"; se l'istanza manca: "Create APO instance failed, Working in bypass mode." (**visto**, stringhe).
- Gli APO interni non passano da CoCreateInstance né dal registro COM (**dedotto** dall'assenza nel hive).

### 2.2 DllGetClassObject dell'APO interno (DolbyAPOvlldp150.dll)
- Export: DllCanUnloadNow 0x18000fae0, DllGetClassObject 0x18000fb20, DllRegisterServer 0x18000fd20, DllUnregisterServer 0x18000fe80 (**visto**).
- 0x18000fb20 è il classico ATL: scorre la object map, confronta il CLSID a 16 byte e restituisce una `CComClassFactory` (**visto**). Voce della object map a 0x1801031c0: pCLSID = 0x180103200 (5CA784EC), crea `CComObject<CDolbyAPOVlldp150>`; supporta anche `CComAggObject` (**visto** RTTI).
- CComClassFactory vtable 0x180103070: CreateInstance 0x180008a00, LockServer 0x180008a90 (**visto**).
- Errore se il modulo non è inizializzato: 0x8000FFFF (0x18000fb64) (**visto**).
- DolbyAPOVR.dll: stessa struttura ATL, classe `CComObject<CDolbyAPO>` (**visto** RTTI).

### 2.3 Layout dell'oggetto e vtable (CComObject<CDolbyAPOVlldp150>)
Ogni interfaccia ha un proprio puntatore a vtable nell'oggetto (offset dall'inizio). Nomi dei metodi confermati dalle stringhe di log in ciascuna funzione (**visto**).

| off | interfaccia | vtable | metodi (slot 3..) |
|---|---|---|---|
| +0x00 | IAudioProcessingObject | 0x180102e58 | Reset 0x18002d890, GetLatency 0x18002a680, GetRegistrationProperties 0x18002a7f0, Initialize 0x18002ade0, IsInputFormatSupported 0x18002c2e0, IsOutputFormatSupported 0x18002c430, GetInputChannelCount 0x18002a5a0; poi virtuali di classe: CheckInitBypassFlag 0x180029600 (13), UpdatePropertyKeys 0x18002e3f0 (15), DolbyModuleExist 0x18002f7e0 (17) |
| +0x08 | IAudioProcessingObjectRT | 0x180102ef0 | APOProcess 0x1800fd050 (sezione RT_CODE), CalcInputFrames 0x1800fd180, CalcOutputFrames 0x1800fd190 (entrambe restituiscono l'argomento: 1 frame in = 1 frame out) |
| +0x10 | IAudioProcessingObjectConfiguration | 0x180102f28 | LockForProcess 0x18002c580, UnlockForProcess 0x18002dd10 |
| +0x18 | IAudioSystemEffects / 2 / 3 | 0x180102f58 | GetEffectsList 0x180029ce0, GetControllableSystemEffectsList 0x18002f920, SetAudioSystemEffectState 0x18002d950 |
| +0x20 | IMMNotificationClient (7991EEC9-7E89-4D85-8390-6C703CEC60C0) | 0x180102f90 | OnDeviceStateChanged, OnDeviceAdded, OnDeviceRemoved, OnDefaultDeviceChanged, OnPropertyValueChanged |
| +0x28 | privata Dolby `IDolbyApoType` (39C334E8-2AF4-4279-9238-19391FDCF35A) | 0x180102fd8 | SetType 0x18002da10, GetType 0x18002ab30 |
| +0x30 | privata Dolby (D26571C4-313E-446D-BFCA-8D2A094927AE) | 0x180103008 | GetSupportedSampleRates 0x18002a940 |
| +0x38 | IAudioProcessingObjectNotifications | 0x180103030 | GetApoNotificationRegistrationInfo 0x1800299c0, HandleNotification 0x18002ac20 |

- Nome di 7991EEC9: **dedotto** IMMNotificationClient (i 5 metodi hanno i nomi `OnDevice...` del log; lo stesso IID è in DAX3API.exe). Ricerca web sul GUID: nessun risultato.
- 39C334E8 = IDolbyApoType: **visto** (il wrapper fa QueryInterface con questo IID a 0x18003001c e in caso di errore scrive `QueryInterface("IDolbyApoType") failed`).
- D26571C4: nome **ignoto**; funzione = GetSupportedSampleRates (**visto**); il wrapper la usa in `GetInnerApoSampleRate` (0x18002ce50..., QI a 0x18002dd68, metodo slot 3 restituisce array di float) (**visto**).

### 2.4 Tabella QueryInterface (ATL interface map a 0x18017f210, sezione RT_CONST)
Voci {IID, offset, 1=semplice} (**visto**):
IAudioSystemEffects +0x18, IAudioSystemEffects2 +0x18, IAudioSystemEffects3 +0x18, IMMNotificationClient +0x20, IAudioProcessingObjectNotifications +0x38, IAudioProcessingObjectRT +0x08, IAudioProcessingObject +0x00, IAudioProcessingObjectConfiguration +0x10, IDolbyApoType +0x28, D26571C4 +0x30. IUnknown = prima voce (regola ATL).
Non presenti: IAudioDeviceModulesClient, IApoAuxiliaryInput*, IApoAcousticEchoCancellation (**visto**: IID assenti nel DLL).
DolbyAPOVR.dll: stessa mappa e stessi offset (vtable CComObject<CDolbyAPO> 0x1801a6808...; APOProcess 0x1801a0210 -> 0x1801a00c8) (**visto**).

### 2.5 Interfacce del wrapper DolbyDax3Apo.dll (mappa a 0x18012d010)
IAPO +0x0, IAPORT +0x8, IAPOConfiguration +0x10, ISE/2/3 +0x18, IAPONotifications +0x20, IAudioDeviceModulesClient (98F37DAC-...) +0x28 (**visto** IID; nome **dedotto** dalla stringa di log). Sull'interno il wrapper chiede: IAPORT, IAPOConfiguration, ISE2, ISE3, IAPONotifications, IDolbyApoType (poi SetType con il nome del tipo), IAudioDeviceModulesClient, IApoAcousticEchoCancellation, IApoAuxiliaryInput* (**visto**, stringhe 0x1800d6790..0x1800d6d80).

## 3. Initialize (CApoBase::Initialize 0x18002ade0; VR 0x1800948b0)

Firma standard `Initialize(UINT32 cbDataSize, BYTE* pbyData)`. Accetta tre dimensioni (**visto**, confronti a 0x18002ae98, 0x18002af08, 0x18002afc4; VR 0x180094968/0x1800949d8/0x180094a94):
- 0x38 = APOInitSystemEffects: legge +0x18 pAPOEndpointProperties e +0x20 pAPOSystemEffectsProperties (0x18002aee0/0x18002aef0).
- 0x58 = APOInitSystemEffects2: +0x18 endpoint, +0x20 effetti, +0x30 pDeviceCollection (AddRef se non nullo), +0x38/+0x3C nSoftwareIoDeviceInCollection / nSoftwareIoConnectorIndex, +0x40 AudioProcessingMode (GUID), +0x50 InitializeForDiscoveryOnly.
- 0x50 = APOInitSystemEffects3 ("CAPX enabled"): +0x18 pAPOEndpointProperties, +0x20 pServiceProvider, +0x28 pDeviceCollection, +0x30/+0x34 indici, +0x38 AudioProcessingMode, +0x48 InitializeForDiscoveryOnly. Con pServiceProvider chiama QueryService per IAudioProcessingObjectLoggingService (698F0107) e IAudioProcessingObjectRTQueueService (ACD65E2F) (**visto** GUID a 0x180125838/0x180125828); il puntatore viene usato senza controllo di nullità (**dedotto** da 0x18002b104).
- Altre dimensioni: "Unexpected APO init structure size: %d" ed errore (**visto**).

Passi successivi (**visto** salvo dove indicato):
- Se pDeviceCollection non è nullo e non è InitializeForDiscoveryOnly: chiama la virtuale DolbyModuleExist (slot 17, 0x18002f7e0) con collection e indici; usa MMDeviceEnumerator, IDeviceTopology, IPart, IKsControl per cercare un modulo Dolby nel DSP (Intel/AMD/"PP module"). Se trovato (HRESULT >= 0): flag oggetto+0x7C = 1, "DSP module detected - bypass mode". Se fallisce: "Dolby PP module not found - legacy mode: processing audio" (0x18002b3c8..0x18002b4d8). Con pDeviceCollection NULL il controllo è saltato (cbz a 0x18002b240).
- Registra la modalità ("processing mode: %s"); CheckInitBypassFlag mette in bypass certe modalità ("Processing mode is %s, bypass processing"); quali modalità: **dedotto** RAW, **ignoto** l'elenco esatto.
- Chiavi di proprietà lette (riferimenti adrp/add, **visto**):
  - PKEY_AudioEndpoint_FormFactor {1da5d803-...},0 e PKEY_AudioEndpoint_GUID ,4; PKEY_AudioEndpoint_Disable_SysFx ,5 (in LockForProcess, Reset, OnDeviceRemoved, IsInputFormatSupported).
  - `PKEY_DAX2_FormFactorOverride` {dd0df94b-53a2-4a92-854e-91f42e28fd7b},0 (nome dalla stringa di log a 0x18002b858).
  - Chiavi Dolby {5510c7ab-dfc2-40d0-a98b-5f77f697005e}, pid 0..35 (tabella statica a 0x180004950; altre letture in 0x1800149b0, 0x180015400, 0x18002f390, 0x18002fd70, 0x180032080). Pid 0, 6, 13 nei controlli di bypass (CheckRuntimeBypassFlag, "DAP VLLDP bypass flag").
  - {0c5e4949-7a67-4b9e-9069-1d6259682436}, pid 3010 e 3011.
  - Nel registro di Windows queste chiavi sono nello store **Properties** dell'endpoint altoparlanti (5510c7ab pid 1-11, 13-23, 25-31, 34, 35; 0c5e4949 pid 3010, 3203), non in FxProperties (**visto**). Quindi lo store da cui il codice le legge è pAPOEndpointProperties (**dedotto**).
- Memoria condivisa per il visualizzatore: nome `{01108CBA-C17B-495F-AAE5-B54B3BB93DA2}`, SDDL `D:(A;;GA;;;LS)(A;;GA;;;SY)`; se fallisce: "Visualizer will be disabled" (non bloccante) (**visto**, stringhe).
- Dipendenze di import da soddisfare per caricare il DLL: audioeng.dll (AERT_Allocate, AERT_Free), AVRT, RTWorkQ (RtwqPutWorkItem, RtwqCreateAsyncResult), ole32 (CoCreateInstance, PropVariantClear...), ADVAPI32 (registro, ETW), KERNEL32 (file mapping, mutex, eventi, thread) (**visto**, tabella di import).

## 4. Formati: IsInputFormatSupported, IsOutputFormatSupported, LockForProcess

CApoBase::IsFormatSupported (0x18002bbe0 circa; VR identico a 0x1800956a0) (**visto**):
- Ottiene UNCOMPRESSEDAUDIOFORMAT dal formato richiesto e da quello opposto; canali = 0 -> E_INVALIDARG.
- Frequenza: richiesta deve essere uguale all'opposta; altrimenti propone quella opposta (nessuna conversione dentro l'APO).
- Se il flag "modulo DSP" (oggetto+0x7C) è attivo: canali in = canali out, altrimenti propone quelli opposti.
- Canali ammessi: 1, 2, 4, 6, 8 (maschera 0x156 a 0x18002bf84); altrimenti propone 2 canali, dwChannelMask 3 (FL|FR).
- Frequenza deve appartenere all'insieme della libreria (metodo slot 15 del LibWrapper); altrimenti propone il valore presente o 48000.
- Tipo: deve essere KSDATAFORMAT_SUBTYPE_IEEE_FLOAT (GUID a 0x180105928); altrimenti propone float, 4 byte per campione, 32 bit validi (0x18002c09c..0x18002c108).
- Esito: S_OK; S_FALSE con formato proposto creato da CreateAudioMediaTypeFromUncompressedAudioFormat; APOERR_FORMAT_NOT_SUPPORTED 0x887D0003 (costante a 0x18002c25c).
- Frequenze della libreria VLLDP: 44100/48000 con blocco 256 (0x100), 88200/96000 con 512 (0x200), 176400/192000 con 0x300 (funzione 0x180020ab8) (**visto** le coppie; significato "dimensione blocco del nucleo" **dedotto**, coerente con il gemello: nucleo a 256 campioni).
- Il wrapper, per VR, filtra le frequenze interne a <= 48000 e fa SRC se l'interno non supporta quella richiesta (GetInnerApoSampleRate, costante 48000.0 a 0x18002e240; "SRC prepare...") (**visto**/**dedotto** per la direzione del filtro).

LockForProcess (CApoBase 0x18002c580; VR CApoBaseDap2 0x180099ff0) (**visto**):
- GetUncompressedAudioFormat su ppInputConnections[0] e ppOutputConnections[0] (errori registrati se falliscono).
- Scrive nel blocco di configurazione della libreria: frequenza (convertita a intero), canali in, canali out; chiama i metodi 4, 8, 9, 7, 6 del LibWrapper; inizializza l'aiutante di elaborazione a oggetto+0x80 (0x1800e90a0) con canali e dimensioni.
- Rilegge PKEY_AudioEndpoint_Disable_SysFx (UpdatePropertyKeys slot 15) e lo stato di bypass (slot 13); registra le notifiche dell'endpoint (RegisterEndpointNotification, 0x18002d5a0 circa).
- Uso di u32MaxFrameCount: **ignoto**.

## 5. APOProcess (RT_CODE)

DolbyAPOvlldp150: IAPORT::APOProcess 0x1800fd050, `this` = oggetto+0x08 (**visto**):
1. Se il byte bypass a this+0x70 (oggetto+0x78) è diverso da zero: chiama 0x1800fde70(oggetto+0x80, out.pBuffer, in.pBuffer, in.u32ValidFrameCount, 0) e copia u32BufferFlags e u32ValidFrameCount da ingresso a uscita. 0x1800fde70 non è un memcpy: per ogni campione moltiplica e somma con guadagni (fmul/fadd a 0x1800fdf38) = rimappatura canali in->out con matrice (**dedotto**). Quindi in bypass l'audio passa invariato (a parità di canali) ma con eventuale up/downmix.
2. Altrimenti chiama il metodo slot 10 dell'oggetto libreria (oggetto+0x8+0x12C148); per VlldpLibWrapperV1_5 restituisce sempre 1 (0x180014a60). Allora chiama 0x1800fe3f0(oggetto+0x80, nIn, ppIn, nOut, ppOut): se la libreria non è pronta (puntatore a +0x12C040 nullo) ritorna senza scrivere l'uscita; altrimenti copia flag e conteggio e va al percorso con accumulo a blocchi (0x1800fe450) o diretto (0x1800fe9c8) secondo un flag a +0x12C048.
3. I percorsi chiamano lo slot 0 del LibWrapper (0x1800fd1e0): gestisce BUFFER_VALID (1) e BUFFER_SILENT (2) (in silenzio azzera il buffer d'ingresso, 0x1800f4760), poi slot 14 (0x1800fd380: copia nei buffer interni, chiama slot 7, 12, 7), slot 12 (0x1800fdcb0) chiama slot 22 (0x1800fd000) che salta a **0x18001dae8(stato=[this+0x158], in, out, frame=[this+0x30])** = nucleo DAP VLLDP (**dedotto**: nome della funzione nucleo ignoto, strutture `dap_vlldp_state_s` visibili in RTTI).
4. Se slot 10 restituisse 0, verrebbe chiamato direttamente lo slot 0 dell'oggetto libreria (0x1800fd128).

DolbyAPOVR: APOProcess 0x1801a0210 -> 0x1801a00c8, stessa struttura (bypass a this+0x70 con 0x1801a14c0; percorso normale 0x1801a1a40; slot 0 del LibWrapper 0x1801a0270 con la stessa gestione dei flag) (**visto**).

Wrapper: CDolbyAPOWrapper::APOProcess fa eventuale SRC e dump WAV (`%s\%s_%d_InnerAPO_In.wav` ecc., se DumpAudio) e chiama l'APOProcess interno (**dedotto** dalle stringhe; percorso non tracciato).

## Ignoti principali
- Cartella esatta da cui il wrapper carica l'APO interno.
- Chi scrive e quando le chiavi 5510c7ab/0c5e4949 (probabilmente DAX3API.exe) e il significato di ciascun pid.
- Elenco esatto delle modalità che mettono in bypass; uso di u32MaxFrameCount; latenza dichiarata.
- Nome di D26571C4; nome della funzione nucleo 0x18001dae8 e suo contratto (layout di `dap_vlldp_state_s`).
- Se pAPOEndpointProperties NULL è tollerato.

## Che cosa deve fare un programma ospite

Per far elaborare un buffer agli altoparlanti come in Windows (due stadi: DolbyAPOVR poi DolbyAPOvlldp150), per ciascun DLL:

1. Fornire gli import: un sostituto di audioeng.dll con AERT_Allocate/AERT_Free, più AVRT, RTWorkQ, ole32/OLEAUT32, ADVAPI32 e KERNEL32 (in un ambiente tipo Wine o con stub propri). Senza audioeng il DLL non si carica.
2. Caricare il DLL, prendere `DllGetClassObject`, chiamarlo con il CLSID (VR `E77F483A-...`, VLLDP `5CA784EC-...`) e IID_IClassFactory, poi `CreateInstance(NULL, IID_IAudioProcessingObject)`. Non serve il wrapper DolbyDax3Apo.dll (fa solo selezione del CLSID dal registro, SRC e log); facoltativo `IDolbyApoType::SetType` con il nome del tipo ("APO_SFX"/"APO_MFX") come fa il wrapper (**dedotto**: effetto di SetType non studiato).
3. QueryInterface per IAudioProcessingObjectRT, IAudioProcessingObjectConfiguration (necessarie), facoltative ISE3 e IAudioProcessingObjectNotifications.
4. `Initialize` con APOInitSystemEffects2 (0x58 byte): CLSID, cbSize; pAPOEndpointProperties = IPropertyStore che restituisca almeno le chiavi Dolby {5510c7ab-...},1..35 e {0c5e4949-...},3010/3011 con i valori del portatile (sono nel hive SOFTWARE, store Properties dell'endpoint `{72a99614-...}`), PKEY_AudioEndpoint_FormFactor (altoparlanti), PKEY_AudioEndpoint_GUID, Disable_SysFx = 0; pAPOSystemEffectsProperties = store (può essere quello di FxProperties); pDeviceCollection = NULL (così salta la ricerca del modulo DSP che porterebbe al bypass); AudioProcessingMode = DEFAULT o MEDIA, non RAW; InitializeForDiscoveryOnly = FALSE. Evitare la versione 3 (richiede un IServiceProvider valido).
5. Negoziare il formato: float 32 bit (IEEE_FLOAT, 4 byte), stessa frequenza in ingresso e uscita (48000 consigliato), canali 1/2/4/6/8 (altoparlanti: 2, maschera 3). Chiamare IsInputFormatSupported/IsOutputFormatSupported e accettare S_OK.
6. `LockForProcess` con un APO_CONNECTION_DESCRIPTOR per lato: pFormat (IAudioMediaType, quindi serve un'implementazione minima di IAudioMediaType/GetUncompressedAudioFormat), buffer allocato dall'ospite, u32MaxFrameCount (es. 480 a 48 kHz).
7. In tempo reale: `APOProcess(1, &in, 1, &out)` con APO_CONNECTION_PROPERTY {pBuffer, u32ValidFrameCount, u32BufferFlags = BUFFER_VALID o BUFFER_SILENT}; frame d'uscita = frame d'ingresso (CalcInputFrames/CalcOutputFrames sono l'identità). L'APO copia flag e conteggio sull'uscita. Concatenare VR -> VLLDP.
8. Chiusura: UnlockForProcess, Release.
9. Verifica di riuscita: se l'uscita è identica all'ingresso, l'APO è in bypass (flag a oggetto+0x78), o per modalità, Disable_SysFx, modulo DSP o chiave di bypass Dolby (5510c7ab pid 0/6/13).

Passo successivo consigliato: studiare `UpdatePropertyKeys` (0x18002e3f0, 0x18002f390, 0x180032080, 0x180015400) per avere la mappa pid -> parametro e il tipo VARIANT atteso, poi costruire un ospite minimo (stub di audioeng + IPropertyStore + IAudioMediaType) e provarlo su un buffer di prova senza audio reale.

# 05 - Condizioni di attivazione dell'elaborazione Dolby (DAX3) sul Yoga Slim 7x

Fase di studio, sola lettura. Fonti: i 14 binari ARM64 del pacchetto `dax3_swc_aposvc` (disassemblato objdump, stringhe, rz-bin),
le INF, i file del DriverStore di Windows e i hive SOFTWARE, SYSTEM e NTUSER.DAT del Windows del proprietario (montato in sola lettura).
Marcatori: **visto** (file e indirizzo o stringa), **dedotto**, **ignoto**. È tutta lettura statica: niente è stato eseguito.
Strumenti di lavoro in `$D/work/05` (scratchpad): `xref.py` (coppie adrp/add verso un indirizzo), `strin.py` (stringhe e chiamate
in un intervallo di codice), `va.py` (byte a un indirizzo virtuale del PE), `regdump.py` (dump di un sottoalbero di un hive esportato con hivexml).

## 0. In breve

L'audio passa dall'elaborazione Dolby su questo portatile se valgono **tutte** queste condizioni (in ordine di catena):

1. L'endpoint "Altoparlanti" ha nelle `FxProperties` i wrapper Dolby come SFX e MFX (messi dall'INF di estensione per `AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001`).
2. Il wrapper (`DolbyDax3Apo.dll`) trova in `HKLM\SOFTWARE\Dolby\Wrapper` il CLSID dell'APO interno e riesce a crearlo; altrimenti lavora in bypass.
3. L'APO interno non va in bypass all'avvio: nessun modulo Dolby nel DSP, libreria inizializzata, modalità di elaborazione accettata.
4. L'APO interno non va in bypass in esecuzione: `Disable_SysFx` non attivo e il flag `vlldp_bypass` / `dap_bypass` dell'endpoint a 0.
5. Il servizio `DAX3API` ha trovato un file di taratura per l'SSID del sistema e ha scritto i parametri nell'endpoint.

Sul portatile, oggi, tutte le condizioni risultano soddisfatte (**visto** nei valori del registro, sezione 4).
Non c'è un controllo di licenza a tempo, trial o di rete nei 14 binari; l'unico controllo crittografico trovato riguarda il lancio di
"Sound Radar". Il file di taratura contiene però un campo `security-key` di 512 byte legato all'ID hardware, il cui verificatore non è
stato trovato (sezione 3).

## 1. Che cosa leggono i DLL e il servizio per decidere se elaborare

### 1.1 Wrapper `DolbyDax3Apo.dll` (CLSID registrati sull'endpoint: SFX `{0EBD8605-...}`, MFX `{0EBD8606-...}`, offload `...8611`/`...8612`)
- **Visto** (str16): legge `SOFTWARE\Dolby\Wrapper\` con i valori `APO_SFX`, `APO_MFX`, `APO_EFX`, `APO_OSFX`, `APO_OMFX` (e `REC_*` per la cattura).
- **Visto** (str16): "QuerySettings() = 0x%08lX, Inner APO clsid = %s, Inner APO path = %s", "Load Inner APO (%s) failed.",
  "Create APO instance failed, Working in bypass mode.". **Dedotto**: se il CLSID manca o non si crea l'istanza, l'audio passa invariato.
- **Visto** (str16): "%s, context = %s, store type = %s, pkey = %s": il wrapper legge chiavi dall'archivio FX dell'endpoint.
- Nessuna API crittografica importata (**visto**, `.hdr.txt`: KERNEL32, OLEAUT32, USER32, ADVAPI32, ole32, SHLWAPI, mm-misc, audioeng).

### 1.2 APO interni: `DolbyAPOVR.dll` (DAPVR, SFX, `tuning-cp`) e `DolbyAPOvlldp150.dll` (VLLDP150, MFX, `tuning-vlldp`)
Codice comune `CApoBase` (sorgente `ApoBase.cpp`). Analizzato in VLLDP150; DAPVR ha le stesse stringhe (`CApoBaseDap2::...`).

Bypass all'avvio, `CApoBase::CheckInitBypassFlag` (**visto**, VLLDP150 `0x180029610`; stringa `0x1801254b0`): tre motivi distinti.
- campo `this+0x7c` diverso da 0 → bypass, con la riga di log "dap2_dsp_instantiated" (`0x180125440`). **Dedotto**: Dolby già istanziato nel DSP.
- metodo virtuale (vtable+0x60) vero → "Processing mode is %s, bypass processing" (`0x1801254f0`, uso a `0x1800296dc`).
  **Dedotto**: modalità di segnale non elaborata (verosimilmente RAW; l'INF dichiara per lo SFX solo DEFAULT, MEDIA, MOVIE, COMMUNICATIONS e per l'MFX anche RAW). Elenco esatto **ignoto**.
- oggetto libreria (`this+0x12c000+0x150`) assente o non inizializzato → bypass con log "dap_cpdp_initialized = 0" (`0x180125550`).

Rilevamento del DSP (**visto**, `APOInitSystemEffects`, `0x18002b3fc`..`0x18002b4a4`): "DolbyModuleExist = 0x%08lX",
"DSP module detected - bypass mode" oppure "Dolby PP module not found - legacy mode: processing audio".
Il controllo usa `CPPAPIHelper` (sorgente `PPAPIHelper.cpp`): topologia del dispositivo, `IKsControl`, id del pin di offload (**visto**, stringhe).
**Dedotto**: interroga il driver Qualcomm via KS; su questo portatile `full_dsp_support` è false nei settings e l'elaborazione avviene nell'APO.
Su Linux non c'è KS: la condizione va fornita come "modulo assente".

Bypass in esecuzione, `CApoBase::UpdateBypassFlag` (**visto**, `0x18002e1c4`): bypass = flag di avvio (`this+0x78`) OPPURE metodo virtuale
vtable+0x70, cioè `CApoBaseVlldp::CheckRuntimeBypassFlag` (**visto**, `0x18002f470`). Quest'ultimo:
- legge dall'archivio proprietà la chiave `{5510C7AB-DFC2-40D0-A98B-5F77F697005E},0` (GUID **visto** a `0x180122098`, pid 0; lettura con IPropertyStore::GetValue, vtable+0x28);
- accetta VT_I4/VT_UI4 (valore diverso da 0 = bypass) o VT_BLOB (primo byte) (**visto**, `0x18002f510`..`0x18002f570`);
- se attivo: log "DAP VLLDP bypass flag = [%d]" e "VLLDP APO bypassed!".
- **Dedotto** (con il rapporto 04): pid 0 della famiglia VLLDP è `vlldp_bypass`; per DAPVR l'analogo è `{F112024A-FE30-42A8-80AB-8DD825A06F78},0` = `dap_bypass`.
- Inoltre `CApoBase::UpdatePropertyKeys` registra `PKEY_AudioEndpoint_Disable_SysFx` (`{1DA5D803-D492-4EDD-8C23-E0C0FFEE7F0E},5`),
  `PKEY_AudioEndpoint_FormFactor` e `PKEY_DAX2_FormFactorOverride` (**visto**, stringhe). Che `Disable_SysFx=1` porti al bypass è
  **dedotto** (stringa "Dolby APO is bypassed." nella stessa funzione; il progetto gemello lo riporta come provato).
- DAPVR ha anche "APO instance is reach the ceiling. Audio data will be bypassed." (**visto**). **Dedotto**: limite dato da
  `max_apo_instance_count` dei settings (5 nei settings Lenovo).
- Formato: "Unsupported sample rate: [%d]" in `LibWrapperBase::ValidateApoInfo` (**visto**). Il nome "Validate" non riguarda licenze.

### 1.3 Servizio `DAX3API.exe` (servizio `DolbyDAXAPI`, LocalSystem, avvio automatico: **visto** in SYSTEM\Services)
- Non decide il bypass dell'audio direttamente: scrive i parametri (fra cui i flag di bypass e gli "enable") nelle proprietà dell'endpoint
  tramite `Dax3DapControl.dll` ("Set property key [%s, %s, %d]", **visto**). **Dedotto** dal rapporto 04.
- `WriteDoblyEnableIntoRegistry` (**visto**, `0x1400434c8`): crea `Software\Dolby\DAX` e scrive `DolbyEnable`. È uno **specchio in uscita**:
  nessun APO legge `Software\Dolby\DAX` (stringa assente nei DLL di elaborazione, **visto**). Ruolo verso app esterne: **ignoto**.
- Lo stato Dolby acceso/spento di partenza per endpoint arriva dai settings (`dolby_enabled`, sezione 5) e dallo stato runtime.
- Sceglie il file di taratura (sezione 2) e, se manca, non procede (non c'è ripiego sul file generico per l'altoparlante interno).
- Marcatore di "dispositivo abilitato Dolby": l'INF di estensione scrive `HKR,"EP\\0","{6CA6A085-3041-482B-9113-C61E7F250356},0" = "0.4.0"`
  (**visto**, `dax3_ext_qc.inf` riga 469, commento "Add Dolby enabled device indicator string here"). La GUID compare una volta in
  DAX3API, Dax3DapControl, VR e VLLDP150 (**visto**, ricerca nei byte); chi la legge e con quale effetto: **ignoto** (nessun riferimento diretto adrp/add).

## 2. Scelta del file di taratura

### 2.1 Dall'INF ai file
- `dax3_ext_qc.inf` (**visto**): l'estensione `DeviceExtension_Install_DolbyAccessNoGaming_V2` si applica a `AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001`
  (riga 32). Copia tutti i file di taratura e i settings nella cartella del driver (`DestinationDirs = 13`) e scrive `HKR, , DaxExtFolder, ,%13%`.
- L'INF **non** contiene regole che associno un hardware ID a un file: la scelta è a runtime per nome.
- Valore reale (**visto**, SYSTEM): `ControlSet001\Control\Class\{4d36e96c-...}\0003\DaxExtFolder =
  C:\WINDOWS\System32\DriverStore\FileRepository\dax3_ext_qc.inf_arm64_e5f18b7b3bf0fb11` (chiave driver del dispositivo AUCD).
  Nella stessa chiave `Settings\DolbySlidingBass = 0` (scritto da DAX3API, stringa vista).

### 2.2 SSID del sistema (DAXSSID.dll, `GetSSID`)
- DAX3API `getSystemId` (**visto**, `0x140049650`) chiama `DAXSSID!GetSSID` (import visto, IAT `0x1401e0098`), con ripetizioni ogni 200 ms fino a 50 volte
  ("Cannot queried system ID. Sleep %dms and retry", **visto** `0x140049744` e `0x1400497e8`), poi `GetTuningFileName` con un ciclo analogo
  ("NO Tuning File Found! Sleep %dms and retry").
- DAXSSID costruisce l'SSID dagli ID hardware con formati **visti**: `%s_DEV_%s_SUBSYS_%s` (`0x1800410c0`), poi `AppendParentId` con
  `_%s_SUBSYS_%s` (`0x1800412a8`), log "Confirm appended parent SSID: %s". Esiste un filtro sul produttore ("Skip device, Vendor Id not in
  supported list, VEN = %s") e varianti per HDAUDIO, INTELAUDIO, SoundWire/SDCA, USB, PCI.
- Dispositivi reali (**visto**, SYSTEM\Enum): `AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001` (driver `qcaudminiport8380`, chiave `...\0003`)
  figlio di `ADCM\VEN_QCOM&DEV_0CC1&SUBSYS_IDEA4001`.
- **Dedotto**: SSID = `AUCD` + `_DEV_0C29_SUBSYS_IDEA4001` + `_ADCM_SUBSYS_IDEA4001` = `AUCD_DEV_0C29_SUBSYS_IDEA4001_ADCM_SUBSYS_IDEA4001`,
  cioè il nome del file senza `.xml`.

### 2.3 Ricerca del file (`DolbyEndpointControl::LoadTuningWithHardwareID`, **visto** `0x14006b2d0`)
- Log "Ready to search tuning file in folder: %s" (cartella = `DaxExtFolder`), poi l'ID viene ripulito dai caratteri `\/:*?"<>|`,
  i caratteri regex `{}[]().^$+` vengono protetti con `\`, e si aggiunge `.*\.xml`; log "Ready to search tuning file by pattern: %s",
  "Tuning file for current device: %s" oppure "There is no specific tuning file for this hardware id : [%s]." (**visto**, stringhe e riferimenti).
- Dettaglio esatto della sostituzione: **ignoto** (non decompilato riga per riga).
- File presente (**visto**): `AUCD_DEV_0C29_SUBSYS_IDEA4001_ADCM_SUBSYS_IDEA4001.xml` nel DriverStore, identico alla copia in `$D/pkg` (cmp).

### 2.4 Se il file non c'è
- Per l'altoparlante interno: "NO Tuning File Found! Please check with your driver vendor! [systemId = %s]" in
  `GetInternalSpeakerTuningParser` e "Cannot find tuning file!" (**visto**). Nessun ripiego per l'interno trovato.
- `Speaker_Default_Atmos3.8.xml` e `Headphone_Default_Generic_Default_Atmos3.8.xml` servono ai dispositivi **esterni**:
  `DAXAPIImplement::QueryExternalTuningFiles` usa i modelli `Speaker_(?:` / `Headphone_(?:` ... `|Default)[\S\s]*(\.xml)` (**visto**);
  un endpoint non integrato viene trattato come cuffia ("Audio endpoint will be treated as headphone because it is not built-in speaker", **visto**).
  **Dedotto**: Speaker_Default è la taratura generica per altoparlanti esterni, non il ripiego dell'interno.
- Differenze utili: Speaker_Default ha `settings_filename = default_settings.json` e `security-key` vuoto; il file IDEA4001 punta a
  `operator_settings_lenovo_default.json` (**visto**).

## 3. Verifiche di integrità o licenza

### 3.1 API crittografiche importate
- Solo `DAX3API.exe` importa crittografia: CRYPT32 `CryptQueryObject`, `CryptMsgGetParam`, `CryptMsgClose`, `CertFindCertificateInStore`,
  `CertGetNameStringW`, `CertCloseStore`, `CertFreeCertificateContext` (**visto**, `.hdr.txt` righe 583-591). Nessun `bcrypt`, `wintrust`, `ncrypt`.
- Gli altri 13 binari non importano crittografia (**visto**). `api-ms-win-security-systemfunctions` compare solo come stringa del runtime C.
- Nei 14 binari non ci sono tabelle SHA-1/SHA-2/MD5/AES/CRC32; le uniche sequenze ASN.1 RSA/SHA-256 sono nella firma Authenticode
  in coda a ogni file (stesso conteggio in tutti, **visto** con ricerca di byte).

### 3.2 `CheckCertificate` (unico controllo crittografico trovato)
- Funzione a `0x14015ab18` (**visto**: unica funzione che chiama in sequenza CryptQueryObject, CryptMsgGetParam, CertFindCertificateInStore,
  CertGetNameStringW). Chiamata da `0x140105ce4` dentro `PluginManager::StartSoundRadarHost`.
- Che cosa verifica (**dedotto** da stringhe vicine "DigiCert Trusted G4 Code Signing RSA4096 SHA384 2021 CA1", "Dolby Laboratories, Inc.",
  "CheckCertificate passed/failed : [%s]"): che l'eseguibile di Sound Radar copiato da Dolby Access sia firmato da Dolby Laboratories.
- Dati usati: il file eseguibile da lanciare e la sua firma. Non tocca l'elaborazione audio.
- Collegato: "Sound Radar cannot run when tuning file is NOT in DriverStore" (**visto**): Sound Radar richiede che la taratura stia sotto
  `C:\WINDOWS\System32\DriverStore\FileRepository\`. Anche questo non riguarda l'elaborazione.

### 3.3 `security-key` nel file di taratura
- **Visto**: `<setting><security-key value="AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001=..."/>` nel file IDEA4001, riga 19: dopo l'ID hardware
  ci sono **512 byte** in esadecimale separati da virgole. Non riportati.
- **Visto** nel DriverStore: la chiave è piena (512 byte, ID uguale a quello del file) in tutti i file con `sku = DolbyAtmos` legati a un dispositivo
  (IDEA4001, IDEA4002, 380617AA, 380817AA, QCASD 17AA3803) e vuota in quelli `sku = DolbyAudio` e nei generici Speaker/Headphone_Default.
- **Visto**: DAX3API legge l'elemento `security-key` in `JsonSettingsManager` (`0x14008d664`/`0x14008d6f8`) e in `XmlSettingsManager`
  (`0x140120b28`/`0x140120bc0`) e lo salva nella mappa dei settings (membro `+0x88` dell'oggetto, `0x14008d718`).
- **Visto**: i byte della chiave non compaiono nel registro (SOFTWARE e SYSTEM, ricerca dei primi 8 byte e del testo).
- **Dedotto**: 512 byte è la lunghezza tipica di una firma RSA-4096; lega l'ID hardware (e verosimilmente lo SKU Atmos) al file.
- **Ignoto**: chi la verifica e con quali conseguenze. Nei 14 binari non c'è codice crittografico riconoscibile che la usi; il consumatore del
  valore salvato non è stato trovato. Dati dell'installazione che entrerebbero in gioco: l'ID hardware `AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001`
  e il contenuto del file di taratura.
- Indizio contrario a un blocco dell'elaborazione: `Speaker_Default_Atmos3.8.xml` ha `sku DolbyAtmos` con chiave vuota ed è un file previsto dal
  pacchetto (**dedotto**: la chiave vuota non impedisce di per sé lo SKU Atmos).

### 3.4 Altro cercato e non trovato
- Nessuna stringa su licenze, trial, scadenze, attivazione online nei 14 binari (**visto**, grep su licen/trial/expir/purchas/entitle).
- "Upsell" (**visto**: `UpsellManager::SetUpsellStatus`, "UpsellSKU = %s") è una funzione RPC per l'app Dolby Access (contenuti a pagamento
  per cuffie: DAHP/DABS). Non legata all'altoparlante interno. **Dedotto**.
- Il servizio controlla se esistono i pacchetti Dolby Access (`DolbyLaboratories.DolbyAccess_rz1tebttyb220`, `DolbyAccessOEM`) per il codec
  spaziale delle cuffie (**visto**, stringhe); sul PC risulta solo `DolbyDigitalPlusDecoderOEM` nella cartella utente.

## 4. Valori reali su questo portatile (sola lettura dai hive)

`HKLM\SOFTWARE\Dolby` (**visto**):
- `DAX`: `DolbyEnable = 1`, `LidClose = 1` (chi scrive LidClose: **ignoto**, la stringa non è nei 14 binari).
- `Fusion`: chiave vuota (DAX3API conosce `Software\Dolby\Fusion`, **visto**).
- `Wrapper`: `APO_SFX` e `APO_OSFX = {E77F483A-...}` (DAPVR, `DolbyAPOVR.dll`); `APO_MFX`, `APO_OMFX`, `APO_EFX = {5CA784EC-...}` (VLLDP150,
  `DolbyAPOvlldp150.dll`). Corrispondenza CLSID→DLL **vista** in `dax3_swc_aposvc_arm64.inf` e nella chiave driver del componente software
  (`SYSTEM\...\Class\{5989fce8-...}\0007\AudioEngine\AudioProcessingObjects`). Secondo Dax3DapControl i due CLSID corrispondono alle versioni
  di libreria "dap2.10/VR" e "vlldp1.5" (**visto** la tabella di stringhe; scelta in base alla taratura **dedotta**).

Endpoint "Altoparlanti" `MMDevices\Audio\Render\{72a99614-9bc3-4e8f-98a7-30283009ad51}` (**visto**):
- `DeviceState = 1` (attivo); FormFactor `{1da5d803-...},0 = 1` (Speakers); dispositivo `{1}.AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001\5&261EA3AF&0&0`.
- `Disable_SysFx` `{1da5d803-...},5`: **assente** → miglioramenti attivi (predefinito).
- Marcatore Dolby `{6ca6a085-...},0 = "0.4.0"`.
- `FxProperties`: SFX `{0EBD8605}`, MFX `{0EBD8606}`, offload SFX/MFX `{0EBD8611}`/`{0EBD8612}`, EFX `{697DA8EE-...}` (Qualcomm ProxyAPO);
  `{d04e05a6-...},0` = GUID nullo; ogni APO collegato a `SWD\DRIVERENUM\{690A2C79-...}#DOLBYAPO_DAX3APOSVC&6&45857B7&0`.
- `FxProperties\{45da5c30-2837-4ac4-b1e2-50acc3865974}\User`: blob `{1b4dab55-...},1/2/4/5` (21 e 2649 byte), `{e36464a1-...},1`, `{d5e60007-...},2`
  (contenuto non decodificato qui).
- Famiglia DAP2 `{f112024a-...}`: pid 0 = 0 (VT_I4) → **dedotto** `dap_bypass = 0`.
- Famiglia VLLDP `{5510c7ab-...}`: pid 0 **assente** → **dedotto** `vlldp_bypass` non impostato = nessun bypass (GetValue torna VT_EMPTY e il
  codice non imposta il flag). Presenti pid 1-35 con valori e blob (parametri di elaborazione, vedi rapporto 04 e 07).
- Altre famiglie presenti: `0c5e4949`, `dc827e12`, `5b5e03cb`, `f19f064d`, `a45429a4` (nomi dei codec spaziali, fra cui "Dolby Atmos for
  Headphones/Speakers").

Servizio e file:
- `SYSTEM\ControlSet001\Services\DolbyDAXAPI`: `Start = 2` (automatico), `ObjectName = LocalSystem`, `ImagePath` nel DriverStore (**visto**).
- `C:\ProgramData\Dolby\DAX3\Runtime.xml`: 175 byte, solo `VisualizerEnabled = false` (**visto**). DAX3API conosce anche `Runtime_*` e
  `Operator_Info_*` sotto `%ProgramData%\Dolby\` (stringhe viste): non presenti.
- Cartella utente: solo il pacchetto `DolbyLaboratories.DolbyDigitalPlusDecoderOEM_rz1tebttyb220` (decodificatore, nessuno stato DAX);
  in NTUSER.DAT solo voci di notifiche/tile per `DolbyAccess` e il decoder (**visto**). Nessuna chiave Dolby di configurazione per utente.

## 5. `operator_settings*.json` e `Operator_Info`

Catena di caricamento (**visto**): la taratura IDEA4001 indica `settings_filename = operator_settings_lenovo_default.json`; ogni variante
dichiara `import` di un file base (`JsonSettingsManager` gestisce `import_settings` e i cicli, stringhe viste). Se il JSON manca, si passa
all'XML ("JSON settings is empty. Attempt to load XML settings.").

`operator_settings_lenovo_default.json` rispetto a `default_settings.json` (**visto**, diff):
- `operator = "Lenovo"` (default "Default"); profilo predefinito `music` per altoparlante e cuffia (default `movie`);
- `dolby_enabled`: acceso per `internal_speaker` e `headphone`, con e senza audio spaziale → **stato iniziale acceso**;
- `capture_stream_detection_enable = false` e lista applicazioni vuota (default true con Skype/Teams);
- `auto_profile_enabled = false`, `show_auto_profile_button = false` (mappa applicazioni→profilo presente ma spenta);
- `max_apo_instance_count = 5`, `full_dsp_support = false`, `override_device_volume = false`, `volume_feedback_enable = true`,
  `dabs_auto_enablement = true`, `dahp_auto_enablement = true`, `geq_maximum_range = 192`, `default_uitheme = "red"`,
  `bypass_stereo_virtualizer` tutto false, `ns.load_ns_apo = false`; mancano `external_speaker` e `cirrus_dbe_mode` (presenti nel default).

Varianti Lenovo (solo differenze, **visto**): `_remove_logo` (operator "Default"), `_default_logo` ("Lenovo_Logo"), `_audio_mirroring`
(mostra il pulsante di duplicazione audio; `_amd` aggiunge `compensate_volume`), `_auto_profile*` (attivano il profilo automatico),
`_capture` (riconoscimento chiamate VoIP), `_capg*` (cuffie Bluetooth Lenovo note), `_detachable` (altoparlanti USB staccabili),
`_edu` (pulsante corso online), `_genx_multimode` (`dual_screen_multi_mode = 4`), `_hybridaudio`, `_override_volume*`, `_disable_vl_feedback`.
Nessuna variante cambia l'elaborazione degli altoparlanti; regolano interfaccia, profili automatici e funzioni accessorie.

`Operator_Info_Lenovo.xml` (**visto**): nome "Lenovo", logo vettoriale e `ModeList` con le modalità normal, laptop, stand, tent, tablet,
lid_close (icone). Usato da `GetOperatorInfo`, `GetDeviceModeName`, `GetDeviceModeIcon` (RPC verso l'interfaccia). **Dedotto**: solo marchio e
modalità del dispositivo mostrate all'utente; la taratura IDEA4001 ha un solo endpoint con `operating_mode = "normal"`.

## 6. Che cosa va reso disponibile perché si comporti come in Windows (stesso portatile)

Dati legittimi di questa installazione (nessuna modifica ai binari):
1. Il file `AUCD_DEV_0C29_SUBSYS_IDEA4001_ADCM_SUBSYS_IDEA4001.xml` così com'è (con la sua `security-key`) e i settings Lenovo con le loro importazioni.
2. L'SSID `AUCD_DEV_0C29_SUBSYS_IDEA4001_ADCM_SUBSYS_IDEA4001` e l'ID hardware `AUCD\VEN_QCOM&DEV_0C29&SUBSYS_IDEA4001`, che sono quelli reali.
3. Per l'APO interno: un archivio proprietà con FormFactor = 1, Disable_SysFx assente/0, i valori `{f112024a}` e `{5510c7ab}` dell'endpoint
   (pid 0 a 0 o assente), il marcatore `{6ca6a085},0 = "0.4.0"`.
4. Risposta "nessun modulo Dolby nel DSP" alla sonda PPAPI e una modalità di elaborazione DEFAULT/MEDIA (non RAW).
5. Il CLSID→DLL dell'APO interno come in `SOFTWARE\Dolby\Wrapper` (o caricare direttamente VLLDP150 e DAPVR).

## 7. Ignoti principali
- Verificatore e conseguenze della `security-key` (forse in un componente non presente fra i 14 binari, o non usata nell'elaborazione).
- Consumatore del marcatore `{6ca6a085},0`.
- Elenco esatto delle modalità di segnale che portano al bypass e algoritmo esatto di trasformazione SSID→modello di ricerca.
- Significato di `processing_mode` 1 e 11 nella taratura e chi scrive `LidClose`.

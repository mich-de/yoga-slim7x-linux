# Dolby DAX3: dipendenze d'ambiente dei DLL di elaborazione (compito 03, 2026-11-17)

Fonti: `$D/dis/<file>.hdr.txt` (import/export), `.str.txt`/`.str16.txt`, disassemblato `objdump -d`, binari in `$D/bin`, hive `SOFTWARE`/`SYSTEM` di `/mnt/win` (ControlSet001), INF in `$D/pkg`, spec di Wine (gitlab.winehq.org, ramo master, scaricate il 2026-11-17).
Legenda: **visto** (fonte e indirizzo), **dedotto**, **ignoto**. Solo lettura statica, nulla eseguito.
File di lavoro in `$D/work/03`: `imports.txt` (import per DLL), `calls.py` (risolve gli argomenti x0–x4 costruiti con adrp/add prima di ogni chiamata via IAT), `calls.txt`, `clsid.txt`, `endpoint_props.txt` (valori della chiave Properties dell'endpoint altoparlanti), `winespec/` (spec di Wine usate per i confronti).

DLL esaminati: `DolbyDax3Apo.dll` (wrapper), `DolbyAPOv251.dll`, `DolbyAPOv2100.dll`, `DolbyAPOvlldp.dll`, `DolbyAPOvlldp150.dll` (variante numerata), `DolbyAPOVR.dll`, `Dax3DapControl.dll`, `Dax3Ref.dll`. Tutti PE **ARM64 puro** (`pei-aarch64-little`, non ARM64EC), subsystem GUI 6.2, DllCharacteristics 0x4160 (ASLR, NX, high-entropy VA, CFG) (**visto**, `objdump -x`). Nessuna sezione delay-import (**visto**).
Sul portatile i DLL che girano davvero sono tre: wrapper SFX/MFX `DolbyDax3Apo.dll` → interno SFX `DolbyAPOVR.dll` `{E77F483A}`, interno MFX `DolbyAPOvlldp150.dll` `{5CA784EC}` (**visto**: `HKLM\SOFTWARE\Dolby\Wrapper` `APO_SFX`/`APO_OSFX`=`{E77F483A…}`, `APO_MFX`/`APO_EFX`/`APO_OMFX`=`{5CA784EC…}`; FxProperties dell'endpoint `{72a99614…}` `{d04e05a6…},5`=`{0EBD8605}`, `,6`=`{0EBD8606}`, `,7`=`{697DA8EE}` Proxy APO Qualcomm). Il resto è codice per altre configurazioni.

## 0. Risposta breve

- Gli import sono **pochi e ordinari**: KERNEL32, ADVAPI32 (registro + ETW), ole32/OLEAUT32 (COM), USER32 (2–3 funzioni ATL), SHLWAPI (1), winmm-mmio (solo il dump WAV di debug), AVRT (MMCSS), **RTWorkQ** (coda di lavoro in tempo reale), **audioeng.dll** (`AERT_Allocate`/`AERT_Free`), PROPSYS (solo `Dax3DapControl`). Nessun import di SetupAPI, cfgmgr32, crittografia, rete, RPC, WinRT, DeviceIoControl, GetSystemFirmwareTable (**visto**, `imports.txt`).
- Le dipendenze vere **non stanno negli import** ma nelle interfacce COM che l'ospite deve fornire: il contratto APO (`IAudioProcessingObject*`, `APOInitSystemEffects2/3`, `IAudioMediaType`), l'`IPropertyStore` dell'endpoint con le **chiavi Dolby** (fmtid `{f112024a…}`, `{5510c7ab…}`, `{3d3d117b…}`), `IMMDeviceEnumerator`/`IMMDevice`, e opzionalmente `IDeviceTopology`/`IKsControl` per cercare un modulo Dolby sul DSP.
- **Sotto Wine ARM64 il caricamento dei DLL è plausibile; l'ostacolo è che Wine non ha un motore audio che ospiti APO** (niente audiodg). Serve un piccolo programma ospite (o un plugin PipeWire/LADSPA che carica i PE) che faccia ciò che fa audiodg: crea l'APO, gli passa i property store, chiama `LockForProcess` e `APOProcess` a blocchi.
- Nessun controllo di licenza, SSID, SMBIOS o firma è presente in questi DLL (**visto**: nessuna stringa né import relativo; il controllo SSID sta in `DAXSSID.dll`/`DAX3API.exe`, fuori da questo compito).

## 1. Import per DLL, raggruppati per area (**visto**, `imports.txt`)

Le colonne "tutti gli APO" valgono per v251, v2100, vlldp, vlldp150, VR, Dax3Ref (stesso scheletro `DolbyApoBase` + ATL + CRT statica); differenze segnalate.

| Area | Funzioni | Chi |
|---|---|---|
| Registro | `RegOpenKeyExW RegGetValueW RegQueryValueExW RegQueryInfoKeyW RegEnumKeyExW RegCreateKeyExW RegSetValueExW RegDeleteKeyW RegDeleteKeyExW RegDeleteValueW RegCloseKey` | tutti tranne Dax3DapControl (solo `RegOpenKeyExW RegGetValueW RegCloseKey`). Scrittura/cancellazione = registrar ATL (`DllRegisterServer`), non usata a regime (**dedotto**: stringhe `.rgs` `ForceRemove`, `InprocServer32 = s '%MODULE%'`) |
| Registro (dinamico) | `RegOpenKeyTransactedW RegCreateKeyTransactedW RegDeleteKeyTransactedW` via `GetProcAddress(GetModuleHandle("Advapi32.dll"))`; `RegisterTypeLibForUser`/`UnRegisterTypeLibForUser` da OLEAUT32 | ATL, solo registrazione (**visto**, `calls.txt`) |
| Sicurezza | `ConvertStringSecurityDescriptorToSecurityDescriptorW` (SDDL `D:(A;;GA;;;LS)(A;;GA;;;SY)`) | v251, v2100, vlldp*, VR, Dax3Ref |
| File | `CreateFileW ReadFile WriteFile SetFilePointerEx GetFileSizeEx FlushFileBuffers FindFirstFileExW FindNextFileW GetTempPathW` | tutti (in gran parte CRT); `SetEndOfFile` solo VR |
| Risorse PE | `FindResourceW FindResourceExW LoadResource LockResource SizeofResource` | tutti; in VR servono per la taratura cuffie predefinita (**visto**: `GetDefaultHeadphoneTuning: Failed to obtain default headphone tuning resource.`) |
| Moduli | `LoadLibraryExW GetProcAddress GetModuleHandleW GetModuleHandleExW GetModuleFileNameW FreeLibrary`; `LoadLibraryW` solo wrapper | tutti |
| Memoria | `HeapAlloc/Free/ReAlloc/Size/Destroy VirtualAlloc VirtualFree VirtualLock VirtualUnlock LocalAlloc LocalFree` | tutti |
| Thread e sincronizzazione | `CreateThread ResumeThread ExitThread GetExitCodeThread CreateEventW OpenEventW SetEvent ResetEvent PulseEvent CreateMutexW OpenMutexW ReleaseMutex WaitForSingleObject(Ex) WaitForMultipleObjects DuplicateHandle Sleep SwitchToThread` SRW lock, condition variable, critical section, FLS | APO con memoria condivisa (v251, v2100, vlldp*, VR, Dax3Ref); il wrapper e Dax3DapControl solo lock e FLS |
| Memoria condivisa con nome | `CreateFileMappingW OpenFileMappingW MapViewOfFile UnmapViewOfFile` | v251, v2100, vlldp*, VR, Dax3Ref |
| Tempo | `QueryPerformanceCounter/Frequency GetSystemTimePreciseAsFileTime GetSystemTimeAsFileTime GetTickCount64` (vlldp) `GetTimeZoneInformation` (VR) | tutti |
| Sistema | `GetNativeSystemInfo IsDebuggerPresent OutputDebugStringW`; `VerSetConditionMask VerifyVersionInfoW` solo Dax3DapControl | — |
| Locale/stringhe | `GetLocaleInfoEx LCMapStringEx CompareStringOrdinal CompareStringEx` ecc. (CRT) | tutti |
| COM/OLE | ole32: `CoCreateInstance CoInitializeEx CoUninitialize CLSIDFromString StringFromGUID2 CoCreateGuid CoTaskMem* PropVariantClear`; OLEAUT32 per ordinale: 2 `SysAllocString`, 4 `SysAllocStringLen`, 6 `SysFreeString`, 7 `SysStringLen`, 149 `SysStringByteLen`, 150 `SysAllocStringByteLen`, 161 `LoadTypeLib`, 163 `RegisterTypeLib`, 186 `UnRegisterTypeLib`, 277 `VarUI4FromStr`, 314 `VarBstrCmp` (ordinali risolti sull'`oleaut32.dll` ARM64 di Windows) | tutti |
| PROPSYS | `PropVariantToStringWithDefault InitPropVariantFromInt32Vector PropVariantGetElementCount PropVariantGetStringElem` | solo Dax3DapControl |
| Audio | **audioeng.dll** `AERT_Allocate AERT_Free` | tutti gli APO, non Dax3Ref né Dax3DapControl |
| Audio tempo reale | **AVRT** `AvSetMmThreadCharacteristicsW("Pro Audio") AvRevertMmThreadCharacteristics`; **RTWorkQ** `RtwqPutWorkItem RtwqCreateAsyncResult` | tutti gli APO tranne il wrapper |
| Multimedia | `mmioOpenW mmioRead/Write/Descend/Ascend/CreateChunk/Close` via `api-ms-win-mm-misc-l1-1-0.dll` | solo wrapper (dump WAV) |
| ETW | `EventRegister EventWriteString EventUnregister` | tutti |
| USER32 | `CharNextW UnregisterClassW CharUpperBuffW` | ATL; nessuna finestra, nessun messaggio |
| SHLWAPI | `PathRemoveFileSpecW` | solo wrapper |
| Console | `ReadConsoleW WriteConsoleW GetConsoleMode SetConsoleCtrlHandler` | CRT statica, inerte in una DLL |

Export (**visto**): gli APO e Dax3Ref esportano solo `DllCanUnloadNow DllGetClassObject DllRegisterServer DllUnregisterServer`; `Dax3DapControl.dll` esporta un'API C: `OpenDapControl CloseDapControl GetDapParam SetDapParam SetDapVariantParam`.

Stringhe di DLL caricate dinamicamente (`api-ms-win-core-winrt-l1-1-0`, `RoInitialize`, `api-ms-win-appmodel-runtime`, `mscoree.dll`, `GetTempPath2W`, `LCMapStringEx`…): sono della CRT/ATL statica, con ripiego se mancano (**dedotto**: stesso elenco identico in tutti i DLL, compreso Dax3DapControl che non usa WinRT).

API insolite o recenti:
- `AERT_Allocate`/`AERT_Free` (audioeng.dll): allocatore per buffer usati nel thread audio in tempo reale; esportato dall'`AudioEng.dll` di Windows (**visto**, ordinali 1 e 2). Non esiste in Wine.
- `RtwqPutWorkItem`/`RtwqCreateAsyncResult` (Windows 8.1+), usati con `IAudioProcessingObjectRTQueueService` (Windows 11) (**dedotto**).
- `APOInitSystemEffects3`, `IAudioSystemEffects3`, `IAudioProcessingObjectNotifications`, `IAudioProcessingObjectLoggingService` (API "CAPX" di Windows 11) (**visto**: stringhe `APO init struct type: APOInitSystemEffects3, CAPX enabled`, `QueryService("IAudioProcessingObjectLoggingService")`, GUID delle interfacce presenti nei binari).
- `IPolicyConfigVistaClient` (non documentata) in Dax3DapControl.
- `VerifyVersionInfoW` con build ≥ **22621** (Windows 11 22H2) in Dax3DapControl (**visto**, `0x180032d8c mov w8,#0x585d` prima di `VerifyVersionInfoW` a `0x180032da8`; scopo **ignoto**, probabilmente sceglie tra wrapper V1 `{0EBD85xx}` e V2 `{0EBD86xx}`).
- `PulseEvent` (deprecata) e `VirtualLock` per i buffer in tempo reale.
- `CreateAudioMediaTypeFromUncompressedAudioFormat`/`GetUncompressedAudioFormat` compaiono nei log ma non tra gli import: **dedotto** linkate staticamente (libreria `audiomediatypecrt` dell'SDK).

## 2. Registro (**visto** salvo dove indicato)

| Chiave / valore | Chi lo legge | Dove | Contenuto su questo portatile |
|---|---|---|---|
| `HKLM\SOFTWARE\Dolby\Wrapper\` valore = tipo (`APO_SFX`, `APO_MFX`, `APO_EFX`, `APO_OSFX`, `APO_OMFX`, `REC_*`, `*_KD*`), REG_SZ con il CLSID dell'APO interno | `DolbyDax3Apo.dll` `CDolbyAPOWrapperChain::QuerySettings` | `RegOpenKeyExW(HKLM=0x80000002, "SOFTWARE\Dolby\Wrapper\", 0, KEY_READ)` a `0x180039f1c`; lettura in `0x180039680` (`RegGetValueW`, `RRF_RT_REG_SZ`) chiamata a `0x180039f40` e, se fallisce, una seconda volta con un altro nome a `0x180039f54` | SFX/OSFX `{E77F483A}` (VR), MFX/EFX/OMFX `{5CA784EC}` (vlldp150) |
| stessa chiave, `DumpAudio` (DWORD) | wrapper | `RegGetValueW` a `0x180039f88` | assente → nessun dump |
| stessa chiave | `Dax3DapControl.dll` `GetApoVersion` | `RegOpenKeyExW` a `0x1800141c4`, `RegGetValueW` a `0x180014240` (nome del valore costruito a runtime, **dedotto** `APO_SFX`/`APO_MFX`) | mappa CLSID → `dap2.5`, `dap2.10`, `vlldp1.5`, ecc. (tabella di stringhe) |
| `HKLM\SOFTWARE\Dolby\DAX` `DolbyEnable`=1, `LidClose`=1 | **non letti** da questi DLL (nessuna stringa); **dedotto** `DAX3API.exe` | — | — |
| Registrazione COM: `Classes\CLSID\{…}\InprocServer32` e `AudioEngine\AudioProcessingObjects\{…}` sotto la **chiave software del dispositivo** `SYSTEM\ControlSet001\Control\Class\{5989fce8-9cd0-467d-8a6a-5419e31529d4}\0007` (HKR dell'INF), non in `HKLM\SOFTWARE\Classes` | audiodg/COM, non i DLL | percorso `%SystemRoot%\System32\DriverStore\FileRepository\dax3_swc_aposvc_arm64.inf_arm64_d496b58e814ffb00\…` | 15 CLSID (`clsid.txt`) |
| Parametri Dolby: proprietà dell'endpoint in `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{72a99614-…}\Properties`, nomi `{f112024a-fe30-42a8-80ab-8dd825a06f78},N` (53 valori) e `{5510c7ab-dfc2-40d0-a98b-5f77f697005e},N` (31 valori), PROPVARIANT serializzati (es. `,2` = VT_I4 0x60) | APO tramite l'`IPropertyStore` dell'endpoint passato in `APOInitSystemEffects2/3` (**dedotto** dai log `LibWrapperBase::UpdatePropertyKeys`, `Failed to get value of property key %s.`); Dax3DapControl tramite `IMMDevice::OpenPropertyStore` (`Failed to open property store in read write mode, try read only mode again`) | tabelle PROPERTYKEY a passo 24 byte nei binari: `{f112024a}` ×70, `{5510c7ab}` ×40, `{3d3d117b-727e-4106-b9c5-bfcfa278555f}` ×21 (presenti in VR, vlldp150, v251, Dax3DapControl, DAX3API.exe; assenti nel wrapper) | `endpoint_props.txt`; `{3d3d117b}` assente dal registro (**dedotto**: chiavi volatili/in tempo reale, vedi `_REALTIME_PARAM`) |
| Chiavi Windows lette dall'endpoint | APO | GUID presenti nei binari | `PKEY_AudioEndpoint_FormFactor` e `_Disable_SysFx` (fmtid `{1da5d803}`), `PKEY_Device_FriendlyName` (`{a45c254e}`), `{78c34fc8}` (DEVPKEY_Device_InstanceId), FX `{d04e05a6}`, `PKEY_DAX2_FormFactorOverride` (fmtid **ignoto**) |

Le stringhe `HKEY_CLASSES_ROOT…HKEY_DYN_DATA`, `CLSID\`, `TypeLib`, `Component Categories` sono del registrar ATL (**dedotto**).

## 3. File e percorsi (**visto**)

- **Nessun XML né JSON** è aperto da questi DLL: nessuna stringa `.xml`, `.json`, `ProgramData`, `DriverStore` (solo nel registro). La taratura `AUCD_…IDEA4001.xml` e i `*settings*.json` li legge **dedotto** `DAX3API.exe`, che poi scrive le chiavi `{f112024a}`/`{5510c7ab}` nell'endpoint.
- Wrapper: percorso dell'APO interno = cartella del proprio DLL (`GetModuleFileNameW` a `0x180026478` + `PathRemoveFileSpecW` a `0x180026488`) + nome dalla tabella `\DolbyApoVr.dll`, `\DolbyAPOvlldp150.dll`, `\DolbyAPOv251.dll`, `\DolbyAPOv2100.dll`, `\DolbyAPOvlldp.dll`, `\DolbyAPOvlldp120/130/140.dll`, `\DolbyAPONs.dll`, `\DolbyAPONs30.dll`, `\Dax3Ref.dll`; poi `LoadLibraryW` (`0x18003b134`) + `GetProcAddress("DllGetClassObject")` (`0x18003b2bc`) (**dedotto** il collegamento fra i passi; i singoli passi **visti**). Esiste anche il ramo `CoCreateInstance(clsid interno, CLSCTX_ALL=0x17, IID_IAudioProcessingObject {FD7F2B29})` a `0x18002f9fc`. Conseguenza: **l'APO interno non ha bisogno di registrazione COM**, basta che il DLL stia accanto al wrapper.
- Dump di debug (solo se `DumpAudio`≠0): `%s\%s_%d_In.wav`, `_Out.wav`, `_InnerAPO_In.wav`, `_InnerAPO_Out.wav` con `mmioOpenW`; cartella `C:\Dolby` o `GetTempPathW` (**dedotto**).
- Risorse PE interne: taratura cuffie predefinita in VR; blocchi base64 incorporati in VR/v251/vlldp (**dedotto**: coefficienti predefiniti).

## 4. Comunicazione con altri processi

**CoCreateInstance** (**visto**, `calls.txt`, CLSID in x0 / IID in x3):

| CLSID | IID | Chi |
|---|---|---|
| `{BCDE0395-E52F-467C-8E3D-C4579291692E}` MMDeviceEnumerator | `{A95664D2…}` IMMDeviceEnumerator | v251, v2100, vlldp*, VR, Dax3Ref, Dax3DapControl |
| `{294935CE-F637-4E7C-A41B-AB255460B862}` PolicyConfigVistaClient | `{568B9108…}` IPolicyConfigVista | Dax3DapControl (`0x180013bcc`) |
| CLSID dell'APO interno (da registro) | `{FD7F2B29…}` IAudioProcessingObject | wrapper (`0x18002f9fc`) |
| `{00000323…}` StdGlobalInterfaceTable, `{0002E005…}` StdComponentCategoriesMgr | — | ATL |

**RPC**: nessuno stub MIDL, nessuna stringa `ncalrpc`/`RpcString*`, nessun import di rpcrt4 (**visto**). L'RPC sta in `DAX3API.exe` (fuori compito).
**Pipe**: nessuna (la sola stringa "broken pipe" è un messaggio errno della CRT).
**Finestre/messaggi**: nessuno (USER32 solo per ATL).
**Oggetti con nome** (**visto**, `SharedMemoryController.cpp`): prefisso `Global\`, nomi `%sMAPPING-FILE-%s`, `%sMAPPING-FILE-MUTEX-%s`, `%sMAPPING-FILE-EVENT-%s` con un GUID; DACL SDDL `D:(A;;GA;;;LS)(A;;GA;;;SY)` (solo LocalService e SYSTEM). GUID usati:
- `{8DEA1553-6A40-446F-AAEA-E50EDE792A6A}`, `{034747D1-5B8D-4030-892C-34A183A14768}`, `{569DCA4C-2613-4B3A-B53D-BA83CF2DEF86}`: v251, v2100, VR, Dax3Ref e `DAX3API.exe`. Usi **dedotti** dai log: parametri in tempo reale (`_REALTIME_PARAM`, `HandleRealTimeParams`), "eyes tracking", copia dell'audio (`SetAudioFormatToSharedMemory`, `AudioMirroring`).
- `{01108CBA-C17B-495F-AAE5-B54B3BB93DA2}`: vlldp*, `DAX3API.exe`, visualizzatore (`Init shared memory failed. Visualizer will be disabled.`).
Tutti i fallimenti sono gestiti degradando la funzione (log "will be disabled"), non bloccando l'audio (**dedotto** dai messaggi). Un thread `WatchLoop` attende gli eventi con MMCSS "Pro Audio".
**ETW**: `EventRegister` con GUID del provider passato dal chiamante (**ignoto**), solo `EventWriteString` (log testuale).

## 5. Dispositivi e driver

- **Nessun IOCTL diretto**: niente `DeviceIoControl`, niente `\\.\`, niente SetupAPI/cfgmgr32 (**visto**).
- **IMMDevice/IPropertyStore**: enumerazione endpoint, `GetDefaultAudioEndpoint`, `OpenPropertyStore`, `RegisterEndpointNotificationCallback` (`IMMNotificationClient`: `OnDeviceStateChanged/Added/Removed/OnDefaultDeviceChanged/OnPropertyValueChanged`) in v251/v2100/vlldp*/VR/Dax3Ref (**visto**, stringhe `CApoBase::*`).
- **Proprietà KS tramite IKsControl**, ottenuto con `IMMDevice::Activate` → `IDeviceTopology` → `IConnector`/`IPart` → filtro wave → `IKsControl` (**visto**: stringhe `CPPAPIHelper::*`, GUID IKsControl, KSPROPSETID_AudioModule `{C034FDB0}`, KSPROPSETID_Topology nei binari vlldp150 e Dax3DapControl; VR e wrapper contengono IKsControl/AudioModule). Scopo: cercare un **modulo Dolby sul DSP** (Intel v1/v2, AMD v1/v2, `GetAudioModuleInstantiationState_Intel`). Se c'è → `DSP module detected - bypass mode`; se non c'è → `Dolby PP module not found - legacy mode: processing audio` (**visto**, stringhe di `APOInitSystemEffects`). Quindi l'assenza di queste interfacce porta l'APO a **elaborare in software**, cioè il caso desiderato.
- Wrapper: `IAudioDeviceModulesClient::SetAudioDeviceModulesManager` (moduli audio del driver), `IApoAcousticEchoCancellation`, `IApoAuxiliaryInput*` (solo per la cattura) (**visto**, stringhe `QueryInterface(...)`).
- Notifiche APO di Windows 11: `APO_NOTIFICATION_TYPE_ENDPOINT_VOLUME`, `_ENDPOINT_PROPERTY_CHANGE`, `_SYSTEM_EFFECTS_PROPERTY_CHANGE` (**visto**); opzionali.

## 6. Valutazione per Wine ARM64 (aarch64, pagine 4 KiB su questo kernel: **visto** `getconf PAGESIZE`)

Stato Wine **visto** sulle spec del ramo master; il comportamento a runtime è **ignoto** finché non si prova. Wine non è installato nella live.

| Dipendenza | Valutazione | Note / come fornirla |
|---|---|---|
| KERNEL32 (file, memoria, thread, eventi, mutex, file mapping, `PulseEvent`, `VirtualLock`, `GetTempPath2W`, `CompareStringOrdinal`, `LCMapStringEx`, `GetSystemTimePreciseAsFileTime`) | normale sotto Wine | tutte presenti nella spec |
| `Global\` + SDDL LS/SY | normale sotto Wine | Wine ignora sostanzialmente le DACL; `Global\` accettato. Senza `DAX3API.exe` nessuno apre l'altra estremità: funzioni secondarie disattivate |
| ADVAPI32 registro, `ConvertStringSecurityDescriptor…` | normale sotto Wine | |
| `HKLM\SOFTWARE\Dolby\Wrapper` | da fornire a mano | importare i 5 valori REG_SZ nel prefisso Wine (o saltare il wrapper e caricare VR/vlldp150 direttamente) |
| Parametri `{f112024a}`/`{5510c7ab}`/`{3d3d117b}` | da fornire a mano | l'ospite implementa un `IPropertyStore` che restituisce i PROPVARIANT copiati da `endpoint_props.txt` (o generati dalla taratura XML come fa `DAX3API.exe`) |
| ETW `EventRegister/EventWriteString` | normale sotto Wine | |
| ole32/OLEAUT32/COM, ATL | normale sotto Wine | |
| `CoCreateInstance(MMDeviceEnumerator)` | normale sotto Wine (mmdevapi) | gli endpoint di Wine non hanno le proprietà Dolby né FormFactor coerenti: da completare nel property store dell'ospite |
| `IMMDevice::Activate(IDeviceTopology)` → `IKsControl` | probabile errore, ma innocuo | mmdevapi di Wine non fornisce la topologia KS (**dedotto**); l'APO va in "legacy mode: processing audio" |
| `IPolicyConfigVistaClient` | da fornire a mano (solo Dax3DapControl) | non implementata in Wine; serve solo all'API di controllo, non all'elaborazione |
| `VerifyVersionInfoW` build ≥ 22621 | da fornire a mano (solo Dax3DapControl) | impostare nel prefisso una versione Windows 11 22H2+ (Wine "win11" dichiara 22000: **dedotto** che il test fallisca) |
| AVRT `AvSetMmThreadCharacteristicsW` | normale sotto Wine | implementata in modo minimo |
| RTWorkQ `RtwqPutWorkItem/RtwqCreateAsyncResult` | normale sotto Wine | `rtworkq.dll` presente in Wine |
| **audioeng.dll** `AERT_Allocate/AERT_Free` | da fornire a mano | DLL finta ARM64 con due export che allocano/liberano memoria allineata (firma da verificare sul `AudioEng.dll` di Windows) |
| `api-ms-win-mm-misc-l1-1-0` (mmio) | normale sotto Wine | Wine mappa `api-ms-win-mm-misc-l1-1-1` → winmm; il loader ignora l'ultima cifra di versione (**dedotto**). Serve solo al dump WAV |
| PROPSYS (Dax3DapControl) | da fornire a mano | `InitPropVariantFromInt32Vector` e `PropVariantGetElementCount` sono **stub** in Wine; le altre due presenti |
| Risorse PE, CFG, ASLR | normale sotto Wine | |
| **Ospite APO** (`IAudioProcessingObject::Initialize` con `APOInitSystemEffects2/3`, `IAudioMediaType`, `LockForProcess`, `APOProcess`, `IServiceProvider` per Logging/RTQueue service, `IAudioSystemEffects3`) | **probabile ostacolo** | Wine non ha audiodg né il contratto APO: va scritto un ospite (programma Wine o plugin che carica i PE). Con APOInitSystemEffects2 (senza CAPX) le interfacce di servizio Windows 11 non servono (**dedotto** dai rami di log) |
| Integrazione col flusso audio Linux | **probabile ostacolo** | servono un ponte PipeWire ↔ processo Wine a bassa latenza (blocchi da 10 ms circa) e il formato float a 48 kHz che l'APO accetta |
| Wine per aarch64 su Fedora 45 | **ignoto** | verificare il pacchetto; servono loader PE ARM64 e pagine 4 KiB (presenti) |

## 7. Ignoti principali

- GUID dei provider ETW e semantica esatta di `PKEY_DAX2_FormFactorOverride`.
- Firma precisa di `AERT_Allocate`/`AERT_Free` (parametri) e se l'APO libera con `AERT_Free` memoria che l'ospite gli passa.
- Come l'APO si comporta se le chiavi `{f112024a}`/`{5510c7ab}` mancano (valori predefiniti interni o bypass).
- A che cosa serve il controllo di build 22621 in Dax3DapControl.
- Contenuto della chiave `{3d3d117b}` (assente nel registro).

## 8. Passo successivo consigliato

Prima di toccare Wine, scrivere **un ospite APO minimo** (un `.exe` ARM64 eseguito sotto Wine, oppure il caricatore PE nativo del progetto gemello `sp11_vlldp_pe_loader.h`) che:
1. carica `DolbyAPOVR.dll` e `DolbyAPOvlldp150.dll` con `LoadLibrary` + `DllGetClassObject` (CLSID `{E77F483A}` e `{5CA784EC}`), senza wrapper né registrazione COM;
2. passa `APOInitSystemEffects2` con un `IPropertyStore` in memoria riempito con i valori di `endpoint_props.txt`, FormFactor = altoparlanti, `Disable_SysFx` = 0;
3. fornisce `audioeng.dll` finta (`AERT_*`) e un `IAudioMediaType` float 48 kHz stereo;
4. elabora un file WAV offline e confronta con una registrazione di Windows.
Se il passo 4 riesce offline, il problema residuo è solo il ponte in tempo reale verso PipeWire.

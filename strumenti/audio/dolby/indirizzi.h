/* Indirizzi delle funzioni dei DLL Dolby del Yoga Slim 7x, versione 3.30812.891.0 (base 0x180000000).
 * Fonte: audio-auto/dolby/06-nucleo.md (lettura statica). Valgono solo per i file con le impronte di
 * audio-auto/dolby/dati/sha256-dll-yoga.txt. */
#ifndef INDIRIZZI_H
#define INDIRIZZI_H
/* DolbyAPOvlldp150.dll: libreria dell'altoparlante (dap_vlldp 1.5) */
#define VLLDP_QUERY_MEMORY	0x18001c598ULL	/* (blocco, fs, max_canali, max_operazioni) -> byte */
#define VLLDP_INIT		0x18001a2f0ULL	/* (blocco, fs, max_canali, max_operazioni, memoria) -> stato */
#define VLLDP_QUERY_SCRATCH	0x18001c658ULL	/* (blocco, fs, canali) -> byte */
#define VLLDP_PROCESS		0x18001dae8ULL	/* (stato, ingresso, uscita, scratch) */
#define VLLDP_BYPASS_OFF	0xC6C		/* stato + questo: 0 = passa invariato, 1 = elabora */
/* impostazione dei parametri: (stato, valore) salvo dove indicato; ogni funzione alza il segno "da ricalcolare" */
#define VLLDP_AO_ENABLE		0x180019c20ULL
#define VLLDP_AO_BANDE		0x180019c78ULL	/* (stato, int32 guadagni[], n): 8 canali x 20 bande, 1/16 dB */
#define VLLDP_REG_SOGLIE	0x18001c9b0ULL	/* (stato, int32 alte[20], int32 basse[20]): ordine del registro di Windows */
#define VLLDP_REG_ISOLATE	0x18001c760ULL	/* (stato, int32 isolate[20]) */
#define VLLDP_REG_OVERDRIVE	0x18001c850ULL
#define VLLDP_REG_TIMBRO	0x18001cb50ULL
#define VLLDP_REG_DIST_EN	0x18001c8b0ULL
#define VLLDP_REG_STRESS	0x18001c908ULL	/* (stato, n, int32 valori[]) come nel gemello */
#define VLLDP_REG_PENDENZA	0x18001c6f0ULL
#define VLLDP_PICCO		0x18001b440ULL
#define VLLDP_POSTGAIN		0x18001b4b0ULL
#define VLLDP_SYSGAIN		0x18001d490ULL
#define VLLDP_MBC_ENABLE	0x18001af30ULL
#define VLLDP_MBC_GRUPPI	0x18001b110ULL	/* (stato, n, int32 *gruppi[]) come nel gemello: 6 valori per gruppo */
#define VLLDP_MBC_DEVIAZIONE	0x18001aed0ULL
#define VLLDP_MBC_AGC		0x18001ae00ULL
#define VLLDP_MBC_LENTO		0x18001af90ULL
#define VLLDP_MBC_MIX		0x18001ae60ULL
#define VLLDP_MBC_POTENZA	0x18001d4f0ULL
#define VLLDP_SB_ENABLE		0x18001d150ULL
#define VLLDP_NG_ENABLE		0x18001b350ULL
#define VLLDP_NG_SOGLIA		0x18001b3c0ULL

/* DolbyAPOVR.dll: libreria dei contenuti (dap_vr). Fonte: 06-nucleo.md par. 2.2 e 3.3 e lettura del codice.
 * La configurazione e' un blocco di 64 byte con la frequenza nei primi 4 e il resto a zero. */
#define VR_QUERY_MEMORY		0x180038178ULL	/* (configurazione) -> byte */
#define VR_INIT			0x180036d98ULL	/* (configurazione, memoria) -> stato */
#define VR_QUERY_SCRATCH	0x1800385d8ULL	/* (configurazione) -> byte */
#define VR_OUTPUT_MODE		0x180037b50ULL	/* (stato, modo, canali d'uscita, matrice) */
#define VR_PREPARE		0x180037d20ULL	/* (stato, 1, ingresso, 0...) -> canali */
#define VR_PROCESS		0x18003e068ULL	/* (stato, uscita, lavoro), risultato per indirizzo */
#endif

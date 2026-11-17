/* Motore di Audio Yoga: la libreria Dolby dell'altoparlante con i profili della taratura del portatile.
 * La cartella deve contenere DolbyAPOvlldp150.dll, sha256-dll-yoga.txt e profili.txt (dati privati); con anche
 * DolbyAPOVR.dll si aggiungono surround virtuale, dialoghi e livellatore. */
#ifndef MOTORE_H
#define MOTORE_H
#define MOTORE_BLOCCO 256
#define MOTORE_RITARDO 176		/* campioni di ritardo della libreria a 48 kHz */
#define MOTORE_BANDE 20
enum { P_DINAMICO, P_FILM, P_MUSICA, P_GIOCO, P_VOCE, P_SPENTO, MOTORE_PROFILI };
typedef struct motore motore_t;
motore_t *motore_apri(const char *cartella);		/* NULL se i file mancano o non sono quelli ammessi */
/* profilo 0..5; spinta in dB (guadagno prima del regolatore dell'altoparlante); surround -1 = come il profilo,
 * 0 spento, 1 acceso; dialoghi -1 = come il profilo, 0 spento, 1..16 quantita'; livellatore -1, 0, 1..10;
 * eq: 20 guadagni in dB sommati alla curva del profilo */
void motore_imposta(motore_t *m, int profilo, float spinta_db, int surround, int dialoghi, int livellatore,
		    const float eq_db[MOTORE_BANDE]);
int motore_contenuti(motore_t *m);			/* 1 se c'e' anche la libreria dei contenuti */
void motore_blocco(motore_t *m, float *const in[2], float *const out[2]);	/* 256 campioni per canale */
const int *motore_frequenze(motore_t *m);		/* centri delle 20 bande, Hz */
void motore_chiudi(motore_t *m);
#endif

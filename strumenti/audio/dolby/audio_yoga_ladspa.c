/* Plugin LADSPA "Audio Yoga": il motore Dolby dell'altoparlante dentro PipeWire.
 * Porte: 2 ingressi, 2 uscite, Profilo (0 Dinamico, 1 Film, 2 Musica, 3 Gioco, 4 Voce, 5 Spento), Spinta (dB),
 * Surround (-1 come il profilo, 0, 1), Dialoghi (-1, 0, 1..16), Livellatore (-1, 0, 1..10), EQ 1..20 (dB). Lavora a blocchi di 256 campioni: ritardo costante di 256 + 176 campioni.
 * Se i file del motore mancano o non sono quelli ammessi (cartella in AUDIO_YOGA_DIR), o la frequenza non e'
 * 48 kHz, l'audio passa invariato con lo stesso ritardo. */
#include "motore.h"
#include <ladspa.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { IN_L, IN_R, OUT_L, OUT_R, PROFILO, SPINTA, SURROUND, DIALOGHI, LIVELLATORE, EQ1, PORTE = EQ1 + MOTORE_BANDE };
typedef struct {
	LADSPA_Data *p[PORTE];
	motore_t *m;
	float in[2][MOTORE_BLOCCO], out[2][MOTORE_BLOCCO], visto[PORTE];
	int pos, primo;
} ay_t;

static LADSPA_Handle crea(const LADSPA_Descriptor *d, unsigned long fs)
{
	ay_t *a = calloc(1, sizeof(*a));
	const char *dir = getenv("AUDIO_YOGA_DIR");

	(void)d;
	if (a && fs == 48000)
		a->m = motore_apri(dir && *dir ? dir : "/var/lib/audio-yoga");
	if (a) {
		a->primo = 1;
		a->visto[SURROUND] = a->visto[DIALOGHI] = a->visto[LIVELLATORE] = -1;
	}
	return a;
}

static void collega(LADSPA_Handle h, unsigned long porta, LADSPA_Data *dati)
{
	if (porta < PORTE)
		((ay_t *)h)->p[porta] = dati;
}

static void attiva(LADSPA_Handle h)
{
	ay_t *a = h;

	memset(a->in, 0, sizeof(a->in)); memset(a->out, 0, sizeof(a->out));
	a->pos = 0; a->primo = 1;
	a->visto[SURROUND] = a->visto[DIALOGHI] = a->visto[LIVELLATORE] = -1;
}

static void elabora(LADSPA_Handle h, unsigned long n)
{
	ay_t *a = h;
	float *in[2] = { a->in[0], a->in[1] }, *out[2] = { a->out[0], a->out[1] };
	unsigned long i;
	int c, cambiato = a->primo;

	for (c = PROFILO; c < PORTE; c++)
		if (a->p[c] && *a->p[c] != a->visto[c]) {
			a->visto[c] = *a->p[c]; cambiato = 1;
		}
	if (cambiato && a->m)
		motore_imposta(a->m, (int)(a->visto[PROFILO] + 0.5f), a->visto[SPINTA], (int)lrintf(a->visto[SURROUND]),
			       (int)lrintf(a->visto[DIALOGHI]), (int)lrintf(a->visto[LIVELLATORE]), &a->visto[EQ1]);
	a->primo = 0;
	for (i = 0; i < n; i++) {
		a->p[OUT_L][i] = a->out[0][a->pos]; a->p[OUT_R][i] = a->out[1][a->pos];
		a->in[0][a->pos] = a->p[IN_L][i]; a->in[1][a->pos] = a->p[IN_R][i];
		if (++a->pos == MOTORE_BLOCCO) {
			if (a->m)
				motore_blocco(a->m, in, out);
			else
				memcpy(a->out, a->in, sizeof(a->out));
			a->pos = 0;
		}
	}
}

static void distruggi(LADSPA_Handle h)
{
	motore_chiudi(((ay_t *)h)->m);
	free(h);
}

static LADSPA_PortDescriptor tipi[PORTE];
static LADSPA_PortRangeHint limiti[PORTE];
static const char *nomi[PORTE];
static char nomi_eq[MOTORE_BANDE][8];
static LADSPA_Descriptor desc = {
	.UniqueID = 4159, .Label = "audio_yoga", .Name = "Audio Yoga", .Maker = "yoga-slim7x-linux", .Copyright = "GPL-2.0",
	.Properties = LADSPA_PROPERTY_HARD_RT_CAPABLE, .PortCount = PORTE, .PortDescriptors = tipi, .PortNames = nomi,
	.PortRangeHints = limiti, .instantiate = crea, .connect_port = collega, .activate = attiva, .run = elabora,
	.cleanup = distruggi,
};

const LADSPA_Descriptor *ladspa_descriptor(unsigned long i)
{
	int c;

	if (i)
		return NULL;
	nomi[IN_L] = "In L"; nomi[IN_R] = "In R"; nomi[OUT_L] = "Out L"; nomi[OUT_R] = "Out R";
	nomi[PROFILO] = "Profilo"; nomi[SPINTA] = "Spinta"; nomi[SURROUND] = "Surround"; nomi[DIALOGHI] = "Dialoghi";
	nomi[LIVELLATORE] = "Livellatore";
	tipi[IN_L] = tipi[IN_R] = LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO;
	tipi[OUT_L] = tipi[OUT_R] = LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO;
	for (c = PROFILO; c < PORTE; c++) {
		tipi[c] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL;
		limiti[c].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_0;
		limiti[c].LowerBound = -12; limiti[c].UpperBound = 12;
		if (c >= EQ1) {
			snprintf(nomi_eq[c - EQ1], sizeof(nomi_eq[0]), "EQ %d", c - EQ1 + 1);
			nomi[c] = nomi_eq[c - EQ1];
		}
	}
	limiti[PROFILO].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_INTEGER | LADSPA_HINT_DEFAULT_MIDDLE;
	limiti[PROFILO].LowerBound = 0; limiti[PROFILO].UpperBound = MOTORE_PROFILI - 1;
	limiti[SPINTA].LowerBound = 0;
	for (c = SURROUND; c <= LIVELLATORE; c++) {	/* -1 = come dice il profilo */
		limiti[c].HintDescriptor = LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_INTEGER | LADSPA_HINT_DEFAULT_MINIMUM;
		limiti[c].LowerBound = -1;
	}
	limiti[SURROUND].UpperBound = 1; limiti[DIALOGHI].UpperBound = 16; limiti[LIVELLATORE].UpperBound = 10;
	return &desc;
}

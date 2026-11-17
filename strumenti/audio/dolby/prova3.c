/* Compito 3 (primo passo): la curva a 20 bande del profilo arriva alla libreria dell'altoparlante.
 *   ./prova3 <cartella dei DLL> <elenco impronte> <profili.txt> [profilo] */
#include "indirizzi.h"
#include "vlldp.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int leggi(const char *file, const char *profilo, const char *nome, int32_t *v, int max)
{
	char riga[4096], p[64], n[128];
	FILE *f = fopen(file, "r");
	int k = -1, pos, i;

	while (f && fgets(riga, sizeof(riga), f)) {
		if (sscanf(riga, "%63s %127s %d%n", p, n, &k, &pos) != 3 || strcmp(p, profilo) || strcmp(n, nome))
			continue;
		char *s = riga + pos;
		for (i = 0; i < k && i < max; i++)
			v[i] = strtol(s, &s, 10);
		fclose(f);
		return k;
	}
	if (f)
		fclose(f);
	return -1;
}

static float a[2][VLLDP_BLOCCO], b[2][VLLDP_BLOCCO];

static double guadagno(vlldp_t *v, double f, double amp, int n)	/* dB sul canale sinistro, seconda meta' */
{
	float *in[2] = { a[0], a[1] }, *out[2] = { b[0], b[1] };
	double e = 0;
	int k, i;

	for (k = 0; k < n; k++) {
		for (i = 0; i < VLLDP_BLOCCO; i++)
			a[0][i] = a[1][i] = amp * sin(2 * M_PI * f * (k * VLLDP_BLOCCO + i) / 48000.0);
		vlldp_elabora(v, in, out);
		for (i = 0; k >= n / 2 && i < VLLDP_BLOCCO; i++)
			e += b[0][i] * b[0][i];
	}
	return 20 * log10(sqrt(e / ((n - n / 2) * VLLDP_BLOCCO)) / (amp / sqrt(2)) + 1e-30);
}

int main(int argc, char **argv)
{
	const char *prof = argc > 4 ? argv[4] : "music";
	char p[1100], nome[64];
	int32_t bande[160], freq[20];
	pe_t img;
	vlldp_t *v;
	int c, i, peggio = 0;
	double g, err, errmax = 0;

	if (argc < 4)
		return 1;
	snprintf(p, sizeof(p), "%s/DolbyAPOvlldp150.dll", argv[1]);
	if (pe_carica(&img, p, argv[2]))
		return 2;
	assert(leggi(argv[3], "costanti", "bande48", freq, 20) == 20);
	for (c = 0; c < 8; c++) {
		snprintf(nome, sizeof(nome), "vlldp.audio-optimizer-bands.ch_%02d", c);
		assert(leggi(argv[3], prof, nome, bande + 20 * c, 20) == 20);
	}
	v = vlldp_apri(&img);
	assert(v);
	*(int *)(vlldp_stato(v) + VLLDP_BYPASS_OFF) = 1;
	/* ottimizzatore spento: piatto */
	vlldp_chiama(v, VLLDP_AO_ENABLE, 0, 0);
	g = guadagno(v, 1000, 0.01, 150);
	printf("ottimizzatore spento, 1 kHz: %+.2f dB\n", g);
	assert(fabs(g) < 0.1);
	/* acceso con la curva del profilo: ogni banda deve uscire con il suo guadagno */
	vlldp_chiama(v, VLLDP_AO_BANDE, (uint64_t)bande, 160);
	vlldp_chiama(v, VLLDP_AO_ENABLE, 1, 0);
	guadagno(v, 1000, 0.01, 100);		/* lascia assestare */
	puts("  banda   Hz   atteso  misurato");
	for (i = 0; i < 20; i++) {
		g = guadagno(v, freq[i], 0.01, freq[i] < 200 ? 400 : 150);
		err = fabs(g - bande[i] / 16.0);
		printf("  %2d  %6d  %+6.2f  %+6.2f%s\n", i, freq[i], bande[i] / 16.0, g, err > 0.5 ? "   <-- fuori" : "");
		if (err > errmax) {
			errmax = err; peggio = i;
		}
	}
	printf("scarto massimo %.2f dB (banda %d)\n", errmax, peggio);
	vlldp_chiudi(v);
	return errmax <= 0.5 ? (puts("OK"), 0) : 3;
}

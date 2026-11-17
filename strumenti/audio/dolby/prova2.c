/* Compito 2: la libreria dell'altoparlante elabora blocchi.   ./prova2 <cartella dei DLL> <elenco impronte> */
#include "indirizzi.h"
#include "vlldp.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static float a[2][VLLDP_BLOCCO], b[2][VLLDP_BLOCCO];

/* elabora n blocchi di un tono (f Hz, ampiezza amp; f = 0: impulso nel primo campione); ritorna il valore efficace
 * dell'uscita degli ultimi blocchi e lascia in *somma una firma dell'uscita */
static double corsa(pe_t *img, int attivo, double f, double amp, int n, double *somma, int *non_validi)
{
	vlldp_t *v = vlldp_apri(img);
	float *in[2] = { a[0], a[1] }, *out[2] = { b[0], b[1] };
	double e = 0, s = 0;
	int k, i, bad = 0;

	if (!v)
		return -1;
	if (attivo >= 0)
		*(int *)(vlldp_stato(v) + VLLDP_BYPASS_OFF) = attivo;
	for (k = 0; k < n; k++) {
		for (i = 0; i < VLLDP_BLOCCO; i++)
			a[0][i] = a[1][i] = f > 0 ? amp * sin(2 * M_PI * f * (k * VLLDP_BLOCCO + i) / 48000.0) : (k == 0 && i == 0 ? amp : 0);
		vlldp_elabora(v, in, out);
		for (i = 0; i < VLLDP_BLOCCO; i++) {
			bad += !isfinite(b[0][i]) || !isfinite(b[1][i]);
			s += b[0][i] * (1 + (k * VLLDP_BLOCCO + i) % 97) + b[1][i] * 0.5;
			if (k >= n / 2)
				e += b[0][i] * b[0][i];
		}
	}
	vlldp_chiudi(v);
	*somma = s; *non_validi = bad;
	return sqrt(e / ((n - n / 2) * VLLDP_BLOCCO));
}

int main(int argc, char **argv)
{
	char p[1100];
	pe_t img;
	double s1, s2, r;
	int bad, at;

	if (argc != 3)
		return 1;
	snprintf(p, sizeof(p), "%s/DolbyAPOvlldp150.dll", argv[1]);
	if (pe_carica(&img, p, argv[2]))
		return 2;
	/* acceso: silenzio resta silenzio, l'impulso esce e si ripete identico, 1 kHz a -40 dBFS passa a 0 dB */
	at = 1;
	r = corsa(&img, at, 0, 0, 188, &s1, &bad);
	assert(bad == 0 && r < 1e-4);
	corsa(&img, at, 0, 0.5, 20, &s1, &bad);
	corsa(&img, at, 0, 0.5, 20, &s2, &bad);
	assert(bad == 0 && s1 != 0 && s1 == s2);
	r = corsa(&img, at, 1000, 0.01, 100, &s1, &bad);
	assert(bad == 0 && fabs(20 * log10(r / (0.01 / sqrt(2)))) < 0.1);
	/* un ingresso non valido non deve uscire ne' restare nello stato */
	r = corsa(&img, at, 1000, NAN, 4, &s1, &bad);
	assert(bad == 0);
	/* spento (stato della libreria appena creata): esce silenzio */
	r = corsa(&img, 0, 1000, 0.01, 20, &s1, &bad);
	assert(bad == 0 && r == 0);
	puts("OK");
	return 0;
}

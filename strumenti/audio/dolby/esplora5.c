/* Esplorazione: livelli d'uscita dei sei profili e effetto di spinta ed equalizzatore.  ./esplora5 <cartella privata> */
#include "motore.h"
#include <math.h>
#include <stdio.h>
static float a[2][MOTORE_BLOCCO], b[2][MOTORE_BLOCCO];
static double liv(motore_t *m, double f, double dbfs, int n)
{
	float *in[2] = { a[0], a[1] }, *out[2] = { b[0], b[1] };
	double e = 0, amp = pow(10, dbfs / 20);
	int k, i;
	for (k = 0; k < n; k++) {
		for (i = 0; i < MOTORE_BLOCCO; i++)
			a[0][i] = a[1][i] = amp * sin(2 * M_PI * f * (k * MOTORE_BLOCCO + i) / 48000.0);
		motore_blocco(m, in, out);
		for (i = 0; k >= n / 2 && i < MOTORE_BLOCCO; i++)
			e += b[0][i] * b[0][i];
	}
	return 20 * log10(sqrt(2 * e / ((n - n / 2) * MOTORE_BLOCCO)) + 1e-30);
}
int main(int argc, char **argv)
{
	static const char *nomi[] = { "Dinamico", "Film", "Musica", "Gioco", "Voce", "Spento" };
	float eq[MOTORE_BANDE] = { 0 };
	motore_t *m = motore_apri(argv[1]);
	int p;
	if (!m)
		return 2;
	puts("profilo     1k@-40  234@-40  234@-20  234@-3   3k@-20   3k@-3   8k@-3");
	for (p = 0; p < MOTORE_PROFILI; p++) {
		motore_imposta(m, p, 0, -1, -1, -1, eq);
		liv(m, 1000, -40, 200);
		printf("%-9s  %+6.1f   %+6.1f   %+6.1f   %+6.1f   %+6.1f  %+6.1f  %+6.1f\n", nomi[p], liv(m, 1000, -40, 300),
		       liv(m, 234, -40, 300), liv(m, 234, -20, 300), liv(m, 234, -3, 300), liv(m, 3000, -20, 300),
		       liv(m, 3000, -3, 300), liv(m, 8000, -3, 300));
	}
	motore_imposta(m, P_MUSICA, 6, -1, -1, -1, eq);
	liv(m, 1000, -40, 200);
	printf("Musica, spinta +6 dB:      1k@-40 %+6.1f   1k@-20 %+6.1f   1k@-3 %+6.1f\n", liv(m, 1000, -40, 300), liv(m, 1000, -20, 300), liv(m, 1000, -3, 300));
	eq[7] = 6;	/* banda 7 = 1031 Hz */
	motore_imposta(m, P_MUSICA, 0, -1, -1, -1, eq);
	liv(m, 1000, -40, 200);
	printf("Musica, eq +6 dB a 1031 Hz: 1031@-40 %+6.1f   469@-40 %+6.1f   2250@-40 %+6.1f\n", liv(m, 1031, -40, 300), liv(m, 469, -40, 300), liv(m, 2250, -40, 300));
	eq[7] = 0;
	printf("libreria dei contenuti: %s\n", motore_contenuti(m) ? "presente" : "assente");
	motore_imposta(m, P_MUSICA, 0, 1, -1, -1, eq); liv(m, 1000, -40, 200);
	printf("Musica + surround acceso:     1k@-40 %+6.1f\n", liv(m, 1000, -40, 300));
	motore_imposta(m, P_MUSICA, 0, -1, -1, 7, eq); liv(m, 1000, -40, 200);
	printf("Musica + livellatore 7:       1k@-40 %+6.1f   1k@-20 %+6.1f\n", liv(m, 1000, -40, 300), liv(m, 1000, -20, 300));
	motore_imposta(m, P_DINAMICO, 0, 0, 0, 0, eq); liv(m, 1000, -40, 200);
	printf("Dinamico con i tre effetti spenti: 1k@-40 %+6.1f\n", liv(m, 1000, -40, 300));
	motore_chiudi(m);
	return 0;
}

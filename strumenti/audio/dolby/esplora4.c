/* Esplorazione (compito 3): effetto di soglie del regolatore e compressore multibanda. Non e' una prova automatica. */
#include "indirizzi.h"
#include "vlldp.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static float a[2][VLLDP_BLOCCO], b[2][VLLDP_BLOCCO];
static double livello(vlldp_t *v, double f, double dbfs, int n)	/* dBFS (picco equivalente) dell'uscita, seconda meta' */
{
	float *in[2] = { a[0], a[1] }, *out[2] = { b[0], b[1] };
	double e = 0, amp = pow(10, dbfs / 20);
	int k, i, bad = 0;
	for (k = 0; k < n; k++) {
		for (i = 0; i < VLLDP_BLOCCO; i++)
			a[0][i] = a[1][i] = amp * sin(2 * M_PI * f * (k * VLLDP_BLOCCO + i) / 48000.0);
		vlldp_elabora(v, in, out);
		for (i = 0; i < VLLDP_BLOCCO; i++) {
			bad += !isfinite(b[0][i]);
			if (k >= n / 2)
				e += b[0][i] * b[0][i];
		}
	}
	return bad ? NAN : 20 * log10(sqrt(2 * e / ((n - n / 2) * VLLDP_BLOCCO)) + 1e-30);
}
static void misura(vlldp_t *v, const char *nome)
{
	printf("%-44s 234 Hz: -20 -> %+6.1f   -3 -> %+6.1f   | 3 kHz: -3 -> %+6.1f\n", nome,
	       livello(v, 234, -20, 300), livello(v, 234, -3, 300), livello(v, 3000, -3, 300));
}
int main(int argc, char **argv)
{
	char p[1100];
	pe_t img;
	vlldp_t *v;
	int32_t alta[20] = { -98, -142, -186, -168, -126, -102 }, bassa[20], iso[20] = { 0 };
	int32_t stress[8] = { 288, 288 };
	int32_t g0[6] = { 4, -80, 8321, 90, 150, 32 }, g1[6] = { 20, -71, 8187, 50, 90, 24 };
	const int32_t *gruppi[2] = { g0, g1 };
	int i, caso = argc > 3 ? atoi(argv[3]) : 0;

	for (i = 0; i < 20; i++)
		bassa[i] = alta[i] - 192;
	snprintf(p, sizeof(p), "%s/DolbyAPOvlldp150.dll", argv[1]);
	if (pe_carica(&img, p, argv[2]))
		return 2;
	v = vlldp_apri(&img);
	*(int *)(vlldp_stato(v) + VLLDP_BYPASS_OFF) = 1;
	misura(v, "predefinito");
	if (caso == 1 || caso == 3) {
		vlldp_chiama(v, VLLDP_REG_SOGLIE, (uint64_t)bassa, (uint64_t)alta);
		vlldp_chiama(v, VLLDP_REG_ISOLATE, (uint64_t)iso, 0);
		misura(v, "soglie (bassa, alta)");
	}
	if (caso == 2) {
		vlldp_chiama(v, VLLDP_REG_SOGLIE, (uint64_t)alta, (uint64_t)bassa);
		misura(v, "soglie (alta, bassa)");
	}
	if (caso == 4) {
		vlldp_chiama(v, VLLDP_REG_SOGLIE, (uint64_t)alta, (uint64_t)bassa);
		vlldp_chiama(v, VLLDP_REG_ISOLATE, (uint64_t)iso, 0);
	}
	if (caso == 5) {	/* soglie (bassa, alta) e stress a meta' */
		vlldp_chiama(v, VLLDP_REG_SOGLIE, (uint64_t)bassa, (uint64_t)alta);
		stress[0] = stress[1] = 144;
	}
	if (caso == 6) {	/* soglie (bassa, alta) e stress zero */
		vlldp_chiama(v, VLLDP_REG_SOGLIE, (uint64_t)bassa, (uint64_t)alta);
		stress[0] = stress[1] = 0;
	}
	if (caso >= 3) {
		vlldp_chiama(v, VLLDP_REG_DIST_EN, 1, 0);
		vlldp_chiama(v, VLLDP_REG_TIMBRO, 12, 0);
		vlldp_chiama(v, VLLDP_REG_PENDENZA, 16, 0);
		vlldp_chiama(v, VLLDP_REG_STRESS, 8, (uint64_t)stress);
		misura(v, "+ distorsione, timbro, pendenza, stress");
	}
	if (caso == 3) {
		vlldp_chiama(v, VLLDP_MBC_GRUPPI, 2, (uint64_t)gruppi);
		vlldp_chiama(v, VLLDP_MBC_POTENZA, (uint64_t)-80, 0);
		vlldp_chiama(v, VLLDP_MBC_MIX, 256, 0);
		vlldp_chiama(v, VLLDP_MBC_ENABLE, 1, 0);
		misura(v, "+ compressore multibanda (2 gruppi)");
	}
	vlldp_chiudi(v);
	return 0;
}

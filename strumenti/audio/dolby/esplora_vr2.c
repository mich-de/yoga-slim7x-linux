/* Esplorazione: effetto dei parametri dei contenuti sul secondo DLL.  ./esplora_vr2 <DLL dir> <impronte> */
#include "indirizzi.h"
#include "vr.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static float a[2][256], b[2][256];
static void liv(vr_t *v, const char *nome, double f, double dbfs, int soloL)
{
	float *in[2] = { a[0], a[1] }, *out[2] = { b[0], b[1] };
	double eL = 0, eR = 0, amp = pow(10, dbfs / 20);
	int k, i, n = 400, bad = 0;
	for (k = 0; k < n; k++) {
		for (i = 0; i < 256; i++) {
			a[0][i] = amp * sin(2 * M_PI * f * (k * 256 + i) / 48000.0);
			a[1][i] = soloL ? 0 : a[0][i];
		}
		vr_elabora(v, in, out);
		for (i = 0; i < 256; i++) {
			bad += !isfinite(b[0][i]) || !isfinite(b[1][i]);
			if (k >= n / 2) { eL += b[0][i] * b[0][i]; eR += b[1][i] * b[1][i]; }
		}
	}
	printf("  %-34s %5.0f Hz a %+3.0f%s -> S %+6.1f  D %+6.1f%s\n", nome, f, dbfs, soloL ? " (solo S)" : "", 20 * log10(sqrt(2 * eL / (n / 2 * 256)) + 1e-30),
	       20 * log10(sqrt(2 * eR / (n / 2 * 256)) + 1e-30), bad ? "  NON VALIDI" : "");
}
int main(int argc, char **argv)
{
	char p[1100];
	pe_t img;
	vr_t *v;
	int32_t mat[16] = { 16384, 0, 0, 16384, 11583, 11583, 8192, 8192, 16384, 0, 0, 16384, 16384, 0, 0, 16384 };
	snprintf(p, sizeof(p), "%s/DolbyAPOVR.dll", argv[1]);
	if (pe_carica(&img, p, argv[2]) || !(v = vr_apri(&img)))
		return 2;
	vr_chiama(v, VR_OUTPUT_MODE, 1, 2, (uint64_t)mat);
	liv(v, "predefinito, modo 1", 1000, -40, 0); liv(v, "predefinito, modo 1", 1000, -3, 0);
	vr_chiama(v, 0x18003ff40ULL, 96, 0, 0);		/* volmax-boost */
	liv(v, "volmax 96", 1000, -40, 0); liv(v, "volmax 96", 1000, -3, 0);
	vr_chiama(v, 0x18003fe90ULL, (uint64_t)-96, 0, 0);	/* system-gain -6 dB */
	liv(v, "volmax 96, system-gain -96", 1000, -40, 0); liv(v, "volmax 96, system-gain -96", 1000, -3, 0);
	vr_chiama(v, 0x18003ff40ULL, 0, 0, 0);
	liv(v, "volmax 0, system-gain -96", 1000, -40, 0);
	vr_chiama(v, 0x18003fe90ULL, 0, 0, 0); vr_chiama(v, 0x18003ff40ULL, 96, 0, 0);
	vr_chiama(v, 0x18003fde0ULL, 96, 0, 0);		/* pregain +6 */
	liv(v, "pregain 96", 1000, -40, 0); liv(v, "pregain 96", 1000, -3, 0);
	vr_chiama(v, 0x18003fde0ULL, 0, 0, 0); vr_chiama(v, 0x18003fd30ULL, 96, 0, 0);	/* postgain +6 */
	liv(v, "postgain 96", 1000, -40, 0); liv(v, "postgain 96", 1000, -3, 0);
	vr_chiama(v, 0x18003fd30ULL, 0, 0, 0);
	vr_chiama(v, 0x1800388f0ULL, 1, 0, 0);		/* regulator-enable */
	liv(v, "+ regolatore", 1000, -40, 0); liv(v, "+ regolatore", 1000, -3, 0);
	vr_chiama(v, 0x180036a80ULL, 1, 0, 0); vr_chiama(v, 0x180036980ULL, 8, 0, 0);	/* dialoghi acceso, quantita' 8 */
	liv(v, "+ dialoghi 8", 1000, -40, 0); liv(v, "+ dialoghi 8", 200, -40, 0);
	vr_chiama(v, 0x180036a80ULL, 0, 0, 0);
	vr_chiama(v, 0x180040a90ULL, 1, 0, 0); vr_chiama(v, 0x180040940ULL, 7, 0, 0);	/* livellatore acceso, 7 */
	liv(v, "+ livellatore 7 (senza dialoghi)", 1000, -40, 0); liv(v, "+ livellatore 7", 1000, -20, 0);
	vr_chiama(v, 0x180040a90ULL, 0, 0, 0);
	vr_chiama(v, 0x180038ed0ULL, 1, 0, 0); vr_chiama(v, 0x180038e40ULL, 96, 0, 0);	/* surround decoder + boost */
	vr_chiama(v, VR_OUTPUT_MODE, 11, 2, (uint64_t)mat);
	liv(v, "modo 11 + decoder surround", 1000, -40, 0); liv(v, "modo 11 + decoder surround", 1000, -40, 1);
	vr_chiama(v, VR_OUTPUT_MODE, 1, 2, (uint64_t)mat);
	liv(v, "di nuovo modo 1", 1000, -40, 1);
	vr_chiudi(v);
	return 0;
}

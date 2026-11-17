/* Prova del plugin senza PipeWire: lo carica come farebbe un ospite LADSPA e lo fa lavorare con blocchi irregolari.
 *   AUDIO_YOGA_DIR=<cartella privata> ./prova_plugin ./audio_yoga.so */
#include <assert.h>
#include <dlfcn.h>
#include <ladspa.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define N 48000
static float inl[N], inr[N], outl[N], outr[N], ctl[25];

static int surround = -1;
static double corsa(const LADSPA_Descriptor *d, int profilo, double f, double dbfs, int passo, int *primo_non_zero)
{
	LADSPA_Handle h = d->instantiate(d, 48000);
	double e = 0, amp = pow(10, dbfs / 20);
	int i, n, fatti = 0;

	memset(ctl, 0, sizeof(ctl)); ctl[0] = profilo; ctl[2] = surround; ctl[3] = ctl[4] = -1;
	for (i = 0; i < N; i++)
		inl[i] = inr[i] = amp * sin(2 * M_PI * f * i / 48000.0);
	for (i = 0; i < 25; i++)
		d->connect_port(h, 4 + i, &ctl[i]);
	d->activate(h);
	while (fatti < N) {		/* blocchi di lunghezza variabile, come puo' fare PipeWire */
		n = passo > 0 ? passo : 1 + (fatti * 7 + 13) % 1500;
		if (n > N - fatti)
			n = N - fatti;
		d->connect_port(h, 0, inl + fatti); d->connect_port(h, 1, inr + fatti);
		d->connect_port(h, 2, outl + fatti); d->connect_port(h, 3, outr + fatti);
		d->run(h, n);
		fatti += n;
	}
	d->cleanup(h);
	for (i = 0, *primo_non_zero = -1; i < N; i++) {
		assert(isfinite(outl[i]) && isfinite(outr[i]));
		if (*primo_non_zero < 0 && fabsf(outl[i]) > 1e-7f)
			*primo_non_zero = i;
		if (i >= N / 2)
			e += outl[i] * outl[i];
	}
	return 20 * log10(sqrt(2 * e / (N / 2)) + 1e-30);
}

int main(int argc, char **argv)
{
	void *so = dlopen(argv[1], RTLD_NOW);
	const LADSPA_Descriptor *d;
	double a, b, c;
	int p1, p2;

	if (!so) {
		fprintf(stderr, "%s\n", dlerror());
		return 1;
	}
	d = ((LADSPA_Descriptor_Function)dlsym(so, "ladspa_descriptor"))(0);
	assert(d && d->PortCount == 29 && !strcmp(d->Label, "audio_yoga"));
	a = corsa(d, 5, 1000, -20, 256, &p1);		/* Spento: invariato */
	b = corsa(d, 5, 1000, -20, 0, &p2);		/* stessa cosa con blocchi irregolari */
	printf("Spento, 1 kHz a -20: %+.2f dB (blocchi da 256), %+.2f dB (irregolari); primo campione non nullo %d e %d\n", a, b, p1, p2);
	assert(fabs(a + 20) < 0.1 && fabs(a - b) < 0.01 && p1 == p2 && p1 >= 256 && p1 <= 256 + 1600);
	if (getenv("SENZA_MOTORE")) {			/* file del motore assenti: tutto passa invariato */
		assert(fabs(corsa(d, 2, 234, -3, 0, &p1) + 3) < 0.1);
		puts("OK (senza motore: passa invariato)");
		return 0;
	}
	c = corsa(d, 2, 234, -40, 0, &p1);		/* Musica: la curva alza i 234 Hz */
	printf("Musica, 234 Hz a -40: %+.2f dB\n", c);
	assert(c > -38 && c < -33);
	a = corsa(d, 2, 234, -3, 0, &p1);		/* e il regolatore trattiene i bassi forti */
	printf("Musica, 234 Hz a -3: %+.2f dB\n", a);
	assert(a < -10);
	if (getenv("CON_CONTENUTI")) {		/* con il secondo DLL: il surround acceso cambia l'uscita di Musica */
		b = corsa(d, 2, 1000, -40, 0, &p1);
		surround = 1; c = corsa(d, 2, 1000, -40, 0, &p1); surround = -1;
		printf("Musica, 1 kHz a -40: %+.2f dB; con il surround acceso %+.2f dB\n", b, c);
		assert(fabs(b - c) > 0.5);
	}
	puts("OK");
	return 0;
}

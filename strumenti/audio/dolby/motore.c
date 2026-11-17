#include "motore.h"
#include "indirizzi.h"
#include "vlldp.h"
#include "vr.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *const nomi[MOTORE_PROFILI] = { "dynamic", "movie", "music", "game", "voice", "off" };
typedef struct {
	int32_t ao[160], ao_en, alte[20], basse[20], iso[20], overdrive, timbro, dist_en, stress[8], pendenza;
	int32_t picco, postgain, sysgain, mbc_en, mbc_n, mbc[4][6], mbc_dev, mbc_agc, mbc_lento, mbc_mix, mbc_pot;
	int32_t sb_en, ng_en, ng_thr;
} profilo_t;
/* parametri dei contenuti a un solo valore: nome nella taratura e funzione della libreria (06-nucleo.md par. 2.2) */
static const struct { const char *nome; uint64_t va; } cp_tab[] = {
	{ "system-gain", 0x18003fe90ULL }, { "calibration-boost", 0x18003fc90ULL }, { "volmax-boost", 0x18003ff40ULL },
	{ "pregain", 0x18003fde0ULL }, { "postgain", 0x18003fd30ULL }, { "volume-modeler-calibration", 0x180040120ULL },
	{ "volume-leveler-out-target", 0x180040080ULL }, { "volume-leveler-in-target", 0x18003ffe0ULL },
	{ "volume-modeler-enable", 0x180040b00ULL }, { "ieq-amount", 0x180040770ULL }, { "ieq-enable", 0x1800408d0ULL },
	{ "volume-leveler-amount", 0x180040940ULL }, { "volume-leveler-enable", 0x180040a90ULL },
	{ "volume-leveler-drc-enable", 0x180040a20ULL },
	{ "bass-enhancer-boost", 0x180036610ULL }, { "bass-enhancer-cutoff-frequency", 0x180036690ULL },
	{ "bass-enhancer-width", 0x180036780ULL }, { "bass-enhancer-enable", 0x180036710ULL },
	{ "audio-optimizer-enable", 0x180036590ULL }, { "graphic-equalizer-enable", 0x180036cc0ULL },
	{ "regulator-speaker-dist-enable", 0x180038a60ULL }, { "regulator-relaxation-amount", 0x1800389e0ULL },
	{ "regulator-timbre-preservation", 0x180038ad0ULL }, { "regulator-overdrive", 0x180038960ULL },
	{ "regulator-enable", 0x1800388f0ULL },
	{ "mi-ieq-steering-enable", 0x1800405a0ULL }, { "mi-dv-leveler-steering-enable", 0x180040540ULL },
	{ "mi-dialog-enhancer-steering-enable", 0x1800404e0ULL }, { "mi-surround-compressor-steering-enable", 0x180040600ULL },
	{ "mi-virt-steering-enable", 0x180040480ULL },
	{ "surround-boost", 0x180038e40ULL }, { "surround-decoder-enable", 0x180038ed0ULL },
	{ "dialog-enhancer-ducking", 0x1800369f0ULL }, { "dialog-enhancer-amount", 0x180036980ULL },
	{ "dialog-enhancer-enable", 0x180036a80ULL },
	{ "bass-extraction-cutoff-frequency", 0x180036800ULL }, { "bass-extraction-enable", 0x180036890ULL },
	{ "height-filter-mode", 0x180036d30ULL }, { "virtualizer-front-speaker-angle", 0x180040290ULL },
	{ "virtualizer-height-speaker-angle", 0x180040310ULL }, { "virtualizer-surround-speaker-angle", 0x180040390ULL },
};
#define NCP ((int)(sizeof(cp_tab) / sizeof(cp_tab[0])))
#define ASSENTE INT32_MIN
typedef struct { int32_t v[NCP], modo, matrice[64]; } contenuti_t;
struct motore {
	pe_t img, img_vr; vlldp_t *v; vr_t *vr; profilo_t p[MOTORE_PROFILI]; contenuti_t c[MOTORE_PROFILI];
	int freq[MOTORE_BANDE]; int prof, surround, dialoghi, livellatore; float spinta, eq[MOTORE_BANDE];
};

/* profili.txt: "<profilo> <nome> <n> v1 v2 ..." */
static int leggi(const char *file, const char *profilo, const char *nome, int32_t *v, int max)
{
	char riga[4096], p[64], n[128];
	FILE *f = fopen(file, "r");
	int k, pos, i;

	while (f && fgets(riga, sizeof(riga), f)) {
		char *s;

		if (sscanf(riga, "%63s %127s %d%n", p, n, &k, &pos) != 3 || strcmp(p, profilo) || strcmp(n, nome))
			continue;
		for (s = riga + pos, i = 0; i < k && i < max; i++)
			v[i] = strtol(s, &s, 10);
		fclose(f);
		return k;
	}
	if (f)
		fclose(f);
	return -1;
}

static int carica_profilo(const char *file, const char *nome, profilo_t *p)
{
	const struct { const char *n; int32_t *v; int max; } campi[] = {
		{ "audio-optimizer-enable", &p->ao_en, 1 }, { "regulator-tuning.threshold_high", p->alte, 20 },
		{ "regulator-tuning.threshold_low", p->basse, 20 }, { "regulator-tuning.isolated_band", p->iso, 20 },
		{ "regulator-overdrive", &p->overdrive, 1 }, { "regulator-timbre-preservation", &p->timbro, 1 },
		{ "regulator-speaker-dist-enable", &p->dist_en, 1 }, { "regulator-stress-amount", p->stress, 8 },
		{ "regulator-distortion-slope", &p->pendenza, 1 }, { "peak-level", &p->picco, 1 },
		{ "postgain", &p->postgain, 1 }, { "system-gain", &p->sysgain, 1 },
		{ "mb-compressor-enable", &p->mbc_en, 1 }, { "mb-compressor-tuning.group_count", &p->mbc_n, 1 },
		{ "mb-compressor-tuning.band_group_0", p->mbc[0], 6 }, { "mb-compressor-tuning.band_group_1", p->mbc[1], 6 },
		{ "mb-compressor-tuning.band_group_2", p->mbc[2], 6 }, { "mb-compressor-tuning.band_group_3", p->mbc[3], 6 },
		{ "mb-compressor-channel-deviation", &p->mbc_dev, 1 }, { "mb-compressor-agc-enable", &p->mbc_agc, 1 },
		{ "mb-compressor-slow-gain-enable", &p->mbc_lento, 1 },
		{ "mb-compressor-band0-slow-gain-mix-level", &p->mbc_mix, 1 },
		{ "mb-compressor-target-power-level", &p->mbc_pot, 1 }, { "sliding-bass-enable", &p->sb_en, 1 },
		{ "noise-gate-enable", &p->ng_en, 1 }, { "noise-gate-threshold", &p->ng_thr, 1 },
	};
	char n[128];
	unsigned i;

	for (i = 0; i < sizeof(campi) / sizeof(campi[0]); i++) {
		snprintf(n, sizeof(n), "vlldp.%s", campi[i].n);
		if (leggi(file, nome, n, campi[i].v, campi[i].max) < 1)
			return -1;
	}
	for (i = 0; i < 8; i++) {
		snprintf(n, sizeof(n), "vlldp.audio-optimizer-bands.ch_%02u", i);
		if (leggi(file, nome, n, p->ao + 20 * i, 20) != 20)
			return -1;
	}
	return p->mbc_n >= 0 && p->mbc_n <= 4 ? 0 : -1;
}

static int carica_contenuti(const char *file, const char *nome, contenuti_t *c)
{
	char n[128];
	int i;

	for (i = 0; i < NCP; i++) {
		snprintf(n, sizeof(n), "cp.%s", cp_tab[i].nome);
		if (leggi(file, nome, n, &c->v[i], 1) < 1)
			c->v[i] = ASSENTE;
	}
	if (leggi(file, nome, "cp.output-mode.processing_mode", &c->modo, 1) < 1 ||
	    leggi(file, nome, "cp.output-mode.mix_matrix", c->matrice, 64) < 4)
		return -1;
	return 0;
}

static int cp_ind(const char *nome)
{
	int i;

	for (i = 0; i < NCP; i++)
		if (!strcmp(cp_tab[i].nome, nome))
			return i;
	return 0;
}

static void applica_contenuti(motore_t *m)
{
	contenuti_t c = m->c[m->prof];
	int i;

	if (!m->vr)
		return;
	if (m->dialoghi >= 0) {		/* scelte dell'utente al posto di quelle del profilo */
		c.v[cp_ind("dialog-enhancer-enable")] = m->dialoghi > 0;
		if (m->dialoghi > 0)
			c.v[cp_ind("dialog-enhancer-amount")] = m->dialoghi;
	}
	if (m->livellatore >= 0) {
		c.v[cp_ind("volume-leveler-enable")] = m->livellatore > 0;
		if (m->livellatore > 0)
			c.v[cp_ind("volume-leveler-amount")] = m->livellatore;
	}
	if (m->surround == 0) {
		c.modo = 1; c.v[cp_ind("surround-decoder-enable")] = 0;
	} else if (m->surround == 1) {
		c.modo = 11; c.v[cp_ind("surround-decoder-enable")] = 1;
		if (c.v[cp_ind("surround-boost")] <= 0)
			c.v[cp_ind("surround-boost")] = 96;
	}
	for (i = 0; i < NCP; i++)
		if (c.v[i] != ASSENTE)
			vr_chiama(m->vr, cp_tab[i].va, (uint64_t)(int64_t)c.v[i], 0, 0);
	vr_chiama(m->vr, VR_OUTPUT_MODE, c.modo, 2, (uint64_t)c.matrice);
}

static void applica(motore_t *m)
{
	const profilo_t *p = &m->p[m->prof];
	const int32_t *gruppi[4] = { p->mbc[0], p->mbc[1], p->mbc[2], p->mbc[3] };
	int32_t ao[160];
	int i, eq = 0;
	vlldp_t *v = m->v;

	memcpy(ao, p->ao, sizeof(ao));
	for (i = 0; i < MOTORE_BANDE; i++) {		/* l'equalizzatore dell'utente si somma alla curva, sui due canali */
		int d = lrintf(m->eq[i] * 16);

		ao[i] += d; ao[20 + i] += d; eq |= d;
	}
	vlldp_chiama(v, VLLDP_SYSGAIN, (uint64_t)(int64_t)(p->sysgain + (int32_t)lrintf(m->spinta * 16)), 0);
	vlldp_chiama(v, VLLDP_POSTGAIN, (uint64_t)(int64_t)p->postgain, 0);
	vlldp_chiama(v, VLLDP_AO_BANDE, (uint64_t)ao, 160);
	vlldp_chiama(v, VLLDP_AO_ENABLE, p->ao_en || eq, 0);
	vlldp_chiama(v, VLLDP_REG_SOGLIE, (uint64_t)p->alte, (uint64_t)p->basse);
	vlldp_chiama(v, VLLDP_REG_ISOLATE, (uint64_t)p->iso, 0);
	vlldp_chiama(v, VLLDP_REG_OVERDRIVE, (uint64_t)(int64_t)p->overdrive, 0);
	vlldp_chiama(v, VLLDP_REG_TIMBRO, (uint64_t)(int64_t)p->timbro, 0);
	vlldp_chiama(v, VLLDP_REG_DIST_EN, p->dist_en, 0);
	vlldp_chiama(v, VLLDP_PICCO, (uint64_t)(int64_t)p->picco, 0);
	vlldp_chiama(v, VLLDP_MBC_POTENZA, (uint64_t)(int64_t)p->mbc_pot, 0);
	vlldp_chiama(v, VLLDP_MBC_GRUPPI, p->mbc_n, (uint64_t)gruppi);
	vlldp_chiama(v, VLLDP_MBC_DEVIAZIONE, (uint64_t)(int64_t)p->mbc_dev, 0);
	vlldp_chiama(v, VLLDP_MBC_AGC, p->mbc_agc, 0);
	vlldp_chiama(v, VLLDP_MBC_LENTO, p->mbc_lento, 0);
	vlldp_chiama(v, VLLDP_MBC_MIX, (uint64_t)(int64_t)p->mbc_mix, 0);
	vlldp_chiama(v, VLLDP_MBC_ENABLE, p->mbc_en, 0);
	vlldp_chiama(v, VLLDP_REG_STRESS, 8, (uint64_t)p->stress);
	vlldp_chiama(v, VLLDP_REG_PENDENZA, (uint64_t)(int64_t)p->pendenza, 0);
	vlldp_chiama(v, VLLDP_SB_ENABLE, p->sb_en, 0);
	vlldp_chiama(v, VLLDP_NG_SOGLIA, (uint64_t)(int64_t)p->ng_thr, 0);
	vlldp_chiama(v, VLLDP_NG_ENABLE, p->ng_en, 0);
	*(int *)(vlldp_stato(v) + VLLDP_BYPASS_OFF) = 1;	/* la libreria nasce muta: 1 = elabora */
	applica_contenuti(m);
}

motore_t *motore_apri(const char *cartella)
{
	motore_t *m = calloc(1, sizeof(*m));
	char dll[1100], vr[1100], imp[1100], prof[1100];
	int32_t f[MOTORE_BANDE];
	int i;

	snprintf(dll, sizeof(dll), "%s/DolbyAPOvlldp150.dll", cartella);
	snprintf(vr, sizeof(vr), "%s/DolbyAPOVR.dll", cartella);
	snprintf(imp, sizeof(imp), "%s/sha256-dll-yoga.txt", cartella);
	snprintf(prof, sizeof(prof), "%s/profili.txt", cartella);
	if (!m || leggi(prof, "costanti", "bande48", f, MOTORE_BANDE) != MOTORE_BANDE)
		goto no;
	for (i = 0; i < MOTORE_BANDE; i++)
		m->freq[i] = f[i];
	for (i = 0; i < MOTORE_PROFILI; i++)
		if (carica_profilo(prof, nomi[i], &m->p[i]) || carica_contenuti(prof, nomi[i], &m->c[i]))
			goto no;
	if (pe_carica(&m->img, dll, imp))
		goto no;
	m->v = vlldp_apri(&m->img);
	if (!m->v) {
		pe_scarica(&m->img);
		goto no;
	}
	if (!pe_carica(&m->img_vr, vr, imp)) {		/* facoltativa: senza, restano i soli profili dell'altoparlante */
		m->vr = vr_apri(&m->img_vr);
		if (!m->vr)
			pe_scarica(&m->img_vr);
	}
	m->prof = P_MUSICA; m->surround = m->dialoghi = m->livellatore = -1;
	applica(m);
	return m;
no:
	free(m);
	return NULL;
}

void motore_imposta(motore_t *m, int profilo, float spinta_db, int surround, int dialoghi, int livellatore,
		    const float eq_db[MOTORE_BANDE])
{
	int i;

	m->prof = profilo < 0 || profilo >= MOTORE_PROFILI ? P_MUSICA : profilo;
	m->spinta = isfinite(spinta_db) ? fminf(fmaxf(spinta_db, 0), 12) : 0;
	m->surround = surround < 0 ? -1 : surround > 0;
	m->dialoghi = dialoghi < 0 ? -1 : dialoghi > 16 ? 16 : dialoghi;
	m->livellatore = livellatore < 0 ? -1 : livellatore > 10 ? 10 : livellatore;
	for (i = 0; i < MOTORE_BANDE; i++)
		m->eq[i] = eq_db && isfinite(eq_db[i]) ? fminf(fmaxf(eq_db[i], -12), 12) : 0;
	applica(m);
}

int motore_contenuti(motore_t *m) { return m->vr != NULL; }

void motore_blocco(motore_t *m, float *const in[2], float *const out[2])
{
	float mezzo[2][MOTORE_BLOCCO];
	float *pm[2] = { mezzo[0], mezzo[1] };
	int c, i, bad = 0;

	if (m->vr)			/* prima i contenuti, poi l'altoparlante, come in Windows */
		vr_elabora(m->vr, in, pm);
	vlldp_elabora(m->v, m->vr ? pm : in, out);
	for (c = 0; c < 2; c++)
		for (i = 0; i < MOTORE_BLOCCO; i++)
			bad |= !isfinite(out[c][i]);
	if (bad) {		/* non deve succedere: si rifanno le librerie e questo blocco passa in silenzio */
		vlldp_chiudi(m->v);
		m->v = vlldp_apri(&m->img);
		if (m->vr) {
			vr_chiudi(m->vr);
			m->vr = vr_apri(&m->img_vr);
		}
		if (m->v)
			applica(m);
		for (c = 0; c < 2; c++)
			memset(out[c], 0, MOTORE_BLOCCO * sizeof(float));
	}
}

const int *motore_frequenze(motore_t *m) { return m->freq; }

void motore_chiudi(motore_t *m)
{
	if (m) {
		vlldp_chiudi(m->v);
		pe_scarica(&m->img);
		if (m->vr) {
			vr_chiudi(m->vr);
			pe_scarica(&m->img_vr);
		}
		free(m);
	}
}

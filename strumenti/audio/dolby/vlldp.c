#include "vlldp.h"
#include "indirizzi.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* descrittore dei buffer della libreria (stessa forma usata dal progetto gemello): tipo 7 = float */
typedef struct { uint64_t canali, passo, tipo; void *piani; } dlb_buf;
struct vlldp { pe_t *img; void *arena, *lavoro; uint8_t *stato; };

/* sezioni critiche di Windows: il motore e' usato da un solo thread */
static void blocco_niente(void *p) { (void)p; }
static int blocco_vero(void *p) { (void)p; return 1; }
static int blocco_init(void *p, unsigned a, unsigned b) { (void)p; (void)a; (void)b; return 1; }
static const pe_import_t noti[] = {
	{ "EnterCriticalSection", blocco_niente }, { "LeaveCriticalSection", blocco_niente },
	{ "InitializeCriticalSection", blocco_niente }, { "DeleteCriticalSection", blocco_niente },
	{ "TryEnterCriticalSection", blocco_vero }, { "InitializeCriticalSectionEx", blocco_init },
	{ "InitializeCriticalSectionAndSpinCount", blocco_init },
};

vlldp_t *vlldp_apri(pe_t *img)
{
	vlldp_t *v = calloc(1, sizeof(*v));
	size_t lav;

	if (!v || pe_collega(img, noti, sizeof(noti) / sizeof(noti[0])) < 0)
		return NULL;
	v->img = img;
	lav = (uint32_t)win_chiama(pe_ind(img, VLLDP_QUERY_SCRATCH), VLLDP_BLOCCO, 48000, 2, 0, 0);
	v->arena = aligned_alloc(64, 0x20000);		/* la libreria ne chiede 30791 byte */
	v->lavoro = aligned_alloc(64, (lav + 4096 + 63) & ~63UL);
	if (!v->arena || !v->lavoro)
		return NULL;
	memset(v->arena, 0, 0x20000);
	memset(v->lavoro, 0, (lav + 4096 + 63) & ~63UL);
	v->stato = (uint8_t *)win_chiama(pe_ind(img, VLLDP_INIT), VLLDP_BLOCCO, 48000, 2, 0, (uint64_t)v->arena);
	return v->stato ? v : NULL;
}

void vlldp_elabora(vlldp_t *v, float *const in[2], float *const out[2])
{
	float pulito[2][VLLDP_BLOCCO];
	void *pi[2] = { pulito[0], pulito[1] }, *po[2] = { out[0], out[1] };
	dlb_buf bi = { 2, 1, 7, pi }, bo = { 2, 1, 7, po };
	int c, i;

	for (c = 0; c < 2; c++)		/* un campione non valido avvelenerebbe lo stato della libreria per sempre */
		for (i = 0; i < VLLDP_BLOCCO; i++)
			pulito[c][i] = isfinite(in[c][i]) ? in[c][i] : 0;

	win_chiama(pe_ind(v->img, VLLDP_PROCESS), (uint64_t)v->stato, (uint64_t)&bi, (uint64_t)&bo, (uint64_t)v->lavoro, 0);
}

uint8_t *vlldp_stato(vlldp_t *v) { return v->stato; }

uint64_t vlldp_chiama(vlldp_t *v, uint64_t va, uint64_t a1, uint64_t a2)
{
	return win_chiama(pe_ind(v->img, va), (uint64_t)v->stato, a1, a2, 0, 0);
}

void vlldp_chiudi(vlldp_t *v)
{
	if (v) {
		free(v->arena); free(v->lavoro); free(v);
	}
}

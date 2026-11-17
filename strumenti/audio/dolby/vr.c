#include "vr.h"
#include "indirizzi.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint64_t canali, passo, tipo; void *piani; } dlb_buf;	/* tipo 7 = float */
struct vr { pe_t *img; void *arena, *lavoro; uint8_t *stato; };

static void blocco_niente(void *p) { (void)p; }
static int blocco_vero(void *p) { (void)p; return 1; }
static int blocco_init(void *p, unsigned a, unsigned b) { (void)p; (void)a; (void)b; return 1; }
static const pe_import_t noti[] = {
	{ "EnterCriticalSection", blocco_niente }, { "LeaveCriticalSection", blocco_niente },
	{ "InitializeCriticalSection", blocco_niente }, { "DeleteCriticalSection", blocco_niente },
	{ "TryEnterCriticalSection", blocco_vero }, { "InitializeCriticalSectionEx", blocco_init },
	{ "InitializeCriticalSectionAndSpinCount", blocco_init },
};

vr_t *vr_apri(pe_t *img)
{
	static uint32_t cfg[16] = { 48000 };
	vr_t *v = calloc(1, sizeof(*v));
	size_t mem, lav;

	if (!v || pe_collega(img, noti, sizeof(noti) / sizeof(noti[0])) < 0)
		return NULL;
	v->img = img;
	mem = (uint32_t)win_chiama(pe_ind(img, VR_QUERY_MEMORY), (uint64_t)cfg, 0, 0, 0, 0);
	lav = (uint32_t)win_chiama(pe_ind(img, VR_QUERY_SCRATCH), (uint64_t)cfg, 0, 0, 0, 0);
	if (mem < 4096 || mem > (64u << 20) || lav > (64u << 20))
		return NULL;
	mem = (mem + 4096 + 63) & ~63UL; lav = (lav + 4096 + 63) & ~63UL;
	v->arena = aligned_alloc(64, mem); v->lavoro = aligned_alloc(64, lav);
	if (!v->arena || !v->lavoro)
		return NULL;
	memset(v->arena, 0, mem); memset(v->lavoro, 0, lav);
	v->stato = (uint8_t *)win_chiama(pe_ind(img, VR_INIT), (uint64_t)cfg, (uint64_t)v->arena, 0, 0, 0);
	return v->stato ? v : NULL;
}

uint64_t vr_chiama(vr_t *v, uint64_t va, uint64_t a1, uint64_t a2, uint64_t a3)
{
	return win_chiama(pe_ind(v->img, va), (uint64_t)v->stato, a1, a2, a3, 0);
}

void vr_elabora(vr_t *v, float *const in[2], float *const out[2])
{
	float pulito[2][256];
	void *pi[2] = { pulito[0], pulito[1] }, *po[2] = { out[0], out[1] };
	dlb_buf bi = { 2, 1, 7, pi }, bo = { 2, 1, 7, po };
	int c, i;

	for (c = 0; c < 2; c++)
		for (i = 0; i < 256; i++)
			pulito[c][i] = isfinite(in[c][i]) ? in[c][i] : 0;
	if ((uint32_t)win_chiama_zeri(pe_ind(v->img, VR_PREPARE), (uint64_t)v->stato, 1, (uint64_t)&bi) == 2)
		win_chiama(pe_ind(v->img, VR_PROCESS), (uint64_t)v->stato, (uint64_t)&bo, (uint64_t)v->lavoro, 0, 0);
	else
		for (c = 0; c < 2; c++)
			memcpy(out[c], pulito[c], sizeof(pulito[c]));
}

void vr_chiudi(vr_t *v)
{
	if (v) {
		free(v->arena); free(v->lavoro); free(v);
	}
}

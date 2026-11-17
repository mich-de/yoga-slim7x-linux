/* Esplorazione del secondo DLL (DolbyAPOVR.dll): creazione, modalita' d'uscita, un blocco.  ./esplora_vr <DLL dir> <impronte> */
#define _GNU_SOURCE
#include "pe.h"
#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ucontext.h>
#define VR_QUERY_MEMORY 0x180038178ULL
#define VR_INIT 0x180036d98ULL
#define VR_QUERY_SCRATCH 0x1800385d8ULL
#define VR_OUTPUT_MODE 0x180037b50ULL
#define VR_PREPARE 0x180037d20ULL
#define VR_PROCESS 0x18003e068ULL
static pe_t img;
static const char *passo = "?";
static void guasto(int s, siginfo_t *si, void *ctx)
{
	ucontext_t *u = ctx;
	uint64_t pc = u->uc_mcontext.pc, lr = u->uc_mcontext.regs[30];
	fprintf(stderr, "GUASTO (segnale %d) durante '%s': indirizzo %p, pc DLL 0x%llx, chiamante 0x%llx\n", s, passo, si->si_addr,
		(unsigned long long)(pc - (uint64_t)img.base + img.base_prevista), (unsigned long long)(lr - (uint64_t)img.base + img.base_prevista));
	_exit(3);
}
static void nulla(void *p) { (void)p; }
static int vero(void *p) { (void)p; return 1; }
static int initex(void *p, unsigned a, unsigned b) { (void)p; (void)a; (void)b; return 1; }
static const pe_import_t noti[] = {
	{ "EnterCriticalSection", nulla }, { "LeaveCriticalSection", nulla }, { "InitializeCriticalSection", nulla },
	{ "DeleteCriticalSection", nulla }, { "TryEnterCriticalSection", vero }, { "InitializeCriticalSectionEx", initex },
	{ "InitializeCriticalSectionAndSpinCount", initex },
};
typedef struct { uint64_t canali, passo, tipo; void *piani; } dlb_buf;
int main(int argc, char **argv)
{
	struct sigaction sa = { .sa_sigaction = guasto, .sa_flags = SA_SIGINFO };
	char p[1100];
	uint32_t cfg[32] = { 48000 };
	int32_t matrice[100] = { 16384, 0, 0, 16384 };
	static float in[2][256], out[2][256];
	void *pi[2] = { in[0], in[1] }, *po[2] = { out[0], out[1] };
	dlb_buf bi = { 2, 1, 7, pi }, bo = { 2, 1, 7, po };
	uint64_t mem, scr, n;
	uint8_t *arena, *stato, *lavoro;
	int k, i;

	sigaction(SIGSEGV, &sa, NULL); sigaction(SIGBUS, &sa, NULL); sigaction(SIGILL, &sa, NULL);
	snprintf(p, sizeof(p), "%s/DolbyAPOVR.dll", argv[1]);
	if (pe_carica(&img, p, argv[2]) || pe_collega(&img, noti, 7) < 0)
		return 2;
	passo = "query_memory"; mem = (uint32_t)win_chiama(pe_ind(&img, VR_QUERY_MEMORY), (uint64_t)cfg, 0, 0, 0, 0);
	passo = "query_scratch"; scr = (uint32_t)win_chiama(pe_ind(&img, VR_QUERY_SCRATCH), (uint64_t)cfg, 0, 0, 0, 0);
	printf("memoria dello stato %llu byte, di lavoro %llu byte\n", (unsigned long long)mem, (unsigned long long)scr);
	if (mem < 4096 || mem > (256u << 20) || scr > (256u << 20))
		return 4;
	arena = aligned_alloc(64, (mem + 4096 + 63) & ~63UL); lavoro = aligned_alloc(64, (scr + 4096 + 63) & ~63UL);
	memset(arena, 0, mem + 4096); memset(lavoro, 0, scr + 4096);
	passo = "init"; stato = (uint8_t *)win_chiama(pe_ind(&img, VR_INIT), (uint64_t)cfg, (uint64_t)arena, 0, 0, 0);
	printf("stato %p (arena %p)\n", (void *)stato, (void *)arena);
	if (!stato)
		return 5;
	passo = "output_mode"; win_chiama(pe_ind(&img, VR_OUTPUT_MODE), (uint64_t)stato, argc > 3 ? atoi(argv[3]) : 1, 2, (uint64_t)matrice, 0);
	for (k = 0; k < 40; k++) {
		for (i = 0; i < 256; i++)
			in[0][i] = in[1][i] = 0.01 * sin(2 * M_PI * 1000 * (k * 256 + i) / 48000.0);
		passo = "prepare"; n = (uint32_t)win_chiama_zeri(pe_ind(&img, VR_PREPARE), (uint64_t)stato, 1, (uint64_t)&bi);
		if (k == 0)
			printf("prepare -> %llu\n", (unsigned long long)n);
		passo = "process"; win_chiama(pe_ind(&img, VR_PROCESS), (uint64_t)stato, (uint64_t)&bo, (uint64_t)lavoro, 0, 0);
	}
	{
		double e = 0; int bad = 0;
		for (i = 0; i < 256; i++) { e += out[0][i] * out[0][i]; bad += !isfinite(out[0][i]); }
		printf("ultimo blocco: livello %+.2f dB rispetto all'ingresso, non validi %d\n", 20 * log10(sqrt(e / 256) / (0.01 / sqrt(2)) + 1e-30), bad);
	}
	return 0;
}

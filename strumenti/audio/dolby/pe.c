#include "pe.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

__attribute__((visibility("hidden"), aligned(16))) unsigned char win_teb[4096];	/* tutto zero: limite dello stack a +0x10 = 0 */
__attribute__((visibility("hidden"), aligned(16))) unsigned char win_ris[256];	/* risultati restituiti per indirizzo (x8) */
__asm__(".text\n.global win_chiama\n.type win_chiama,%function\nwin_chiama:\n"
	"	mov x16, x0\n	adrp x18, win_teb\n	add x18, x18, :lo12:win_teb\n"
	"	adrp x8, win_ris\n	add x8, x8, :lo12:win_ris\n"
	"	mov x0, x1\n	mov x1, x2\n	mov x2, x3\n	mov x3, x4\n	mov x4, x5\n	br x16\n");
/* come win_chiama con tre argomenti, gli altri registri a zero e quattro argomenti nulli sullo stack */
__asm__(".text\n.global win_chiama_zeri\n.type win_chiama_zeri,%function\nwin_chiama_zeri:\n"
	"	sub sp, sp, #48\n	stp x29, x30, [sp, #32]\n	stp xzr, xzr, [sp]\n	stp xzr, xzr, [sp, #16]\n"
	"	mov x16, x0\n	adrp x18, win_teb\n	add x18, x18, :lo12:win_teb\n"
	"	adrp x8, win_ris\n	add x8, x8, :lo12:win_ris\n"
	"	mov x0, x1\n	mov x1, x2\n	mov x2, x3\n	mov x3, #0\n	mov x4, #0\n	mov x5, #0\n	mov x6, #0\n	mov x7, #0\n"
	"	blr x16\n	ldp x29, x30, [sp, #32]\n	add sp, sp, #48\n	ret\n");

static uint32_t r32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint64_t r64(const uint8_t *p) { uint64_t v; memcpy(&v, p, 8); return v; }

/* shortcut: impronta calcolata con sha256sum del sistema; nel plugin in tempo reale serve una verifica interna */
static int impronta_ammessa(const char *percorso, const char *elenco)
{
	char cmd[1200], imp[80] = "", riga[400];
	FILE *p, *e;
	int ok = 0;

	if (strchr(percorso, '\'') || strlen(percorso) > 1000)
		return 0;
	snprintf(cmd, sizeof(cmd), "sha256sum '%s' 2>/dev/null", percorso);
	p = popen(cmd, "r");
	if (!p)
		return 0;
	if (!fgets(imp, 65, p))
		imp[0] = 0;
	pclose(p);
	e = fopen(elenco, "r");
	if (strlen(imp) != 64 || !e)
		return 0;
	while (fgets(riga, sizeof(riga), e))
		ok |= !strncmp(riga, imp, 64);
	fclose(e);
	return ok;
}

int pe_carica(pe_t *img, const char *percorso, const char *elenco)
{
	FILE *f;
	uint8_t *raw, *base;
	const uint8_t *opt, *sez;
	long n;
	uint32_t i, nsez, dim_img, dim_hdr, rva_rel, dim_rel, off;
	int64_t delta;

	memset(img, 0, sizeof(*img));
	if (!impronta_ammessa(percorso, elenco)) {
		fprintf(stderr, "pe: %s non e' uno dei file ammessi (impronta SHA-256 non in %s)\n", percorso, elenco);
		return -2;
	}
	f = fopen(percorso, "rb");
	if (!f)
		return -1;
	fseek(f, 0, SEEK_END); n = ftell(f); fseek(f, 0, SEEK_SET);
	raw = malloc(n > 0 ? n : 1);
	if (n < 0x400 || !raw || fread(raw, 1, n, f) != (size_t)n || r32(raw) << 16 != 0x5A4D0000u) {
		fclose(f); free(raw); return -1;
	}
	fclose(f);
	opt = raw + r32(raw + 0x3C) + 24;				/* intestazione opzionale */
	nsez = opt[-24 + 6] | opt[-24 + 7] << 8;
	sez = opt + (opt[-24 + 20] | opt[-24 + 21] << 8);
	if (r32(opt - 24) != 0x4550 || (opt[-24 + 4] | opt[-24 + 5] << 8) != 0xAA64 || (opt[0] | opt[1] << 8) != 0x20B) {
		free(raw); return -1;					/* non e' un PE32+ per ARM64 */
	}
	dim_img = r32(opt + 56); dim_hdr = r32(opt + 60);
	rva_rel = r32(opt + 112 + 5 * 8); dim_rel = r32(opt + 112 + 5 * 8 + 4);
	base = mmap(NULL, dim_img, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (base == MAP_FAILED) {
		free(raw); return -1;
	}
	memcpy(base, raw, dim_hdr);
	for (i = 0; i < nsez; i++) {
		const uint8_t *s = sez + i * 40;
		uint32_t va = r32(s + 12), dim = r32(s + 16), pos = r32(s + 20);

		if (dim && pos + dim <= (uint32_t)n && va + dim <= dim_img)
			memcpy(base + va, raw + pos, dim);
	}
	img->base = base; img->dim = dim_img; img->base_prevista = r64(opt + 24);
	free(raw);
	delta = (int64_t)((uint64_t)(uintptr_t)base - img->base_prevista);
	for (off = 0; delta && off + 8 <= dim_rel; ) {			/* rilocazioni: solo DIR64 (tipo 10) */
		const uint8_t *b = base + rva_rel + off;
		uint32_t pag = r32(b), dim = r32(b + 4), k;

		if (dim < 8 || off + dim > dim_rel)
			break;
		for (k = 0; k < (dim - 8) / 2; k++) {
			uint16_t e = b[8 + 2 * k] | b[9 + 2 * k] << 8;
			uint64_t v;

			if (e >> 12 == 0)
				continue;
			if (e >> 12 != 10) {
				fprintf(stderr, "pe: rilocazione di tipo %u non gestita\n", e >> 12);
				pe_scarica(img); return -1;
			}
			v = r64(base + pag + (e & 0xFFF)) + delta;
			memcpy(base + pag + (e & 0xFFF), &v, 8);
		}
		off += dim;
	}
	return 0;
}

static const char **nomi_trappola;
__attribute__((visibility("hidden"))) void trappola_c(uint64_t i)
{
	fprintf(stderr, "pe: il DLL ha chiamato una funzione di Windows non fornita: %s\n", nomi_trappola[i]);
	abort();
}
__asm__(".text\n.type trappola,%function\ntrappola:\n	mov x0, x17\n	b trappola_c\n");
extern void trappola(void);

int pe_collega(pe_t *img, const pe_import_t *noti, int n)
{
	const uint8_t *opt = img->base + r32(img->base + 0x3C) + 24;
	const uint8_t *d = img->base + r32(opt + 112 + 8);		/* directory degli import */
	uint32_t *stub = mmap(NULL, 1 << 20, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	static int base;		/* le trappole di piu' DLL condividono l'elenco dei nomi */
	int tot = 0, i;

	if (!nomi_trappola)
		nomi_trappola = calloc(1 << 15, sizeof(char *));
	if (stub == MAP_FAILED || !nomi_trappola || !r32(opt + 112 + 8))
		return -1;
	for (; r32(d + 12); d += 20) {
		uint32_t oft = r32(d) ? r32(d) : r32(d + 16), ft = r32(d + 16), k;

		for (k = 0; r64(img->base + oft + 8 * k) && base + tot < (1 << 15); k++, tot++) {
			uint64_t e = r64(img->base + oft + 8 * k);
			const char *nome = e >> 63 ? "(per numero)" : (const char *)img->base + (uint32_t)e + 2;
			void *fn = NULL;
			uint32_t *s = stub + 6 * tot;
			void (*h)(void) = trappola;

			for (i = 0; i < n; i++)
				if (!strcmp(nome, noti[i].nome))
					fn = noti[i].fn;
			nomi_trappola[base + tot] = nome;
			s[0] = 0xD2800011u | (uint32_t)(base + tot) << 5;	/* movz x17, #indice */
			s[1] = 0x58000050u;				/* ldr x16, [pc, #8] */
			s[2] = 0xD61F0200u;				/* br x16 */
			memcpy(s + 3, &h, 8);
			if (!fn)
				fn = s;
			memcpy(img->base + ft + 8 * k, &fn, 8);
		}
	}
	__builtin___clear_cache((char *)stub, (char *)(stub + 6 * tot));
	base += tot;
	return tot;
}

void *pe_ind(const pe_t *img, uint64_t va) { return img->base + (va - img->base_prevista); }

void pe_scarica(pe_t *img)
{
	if (img->base)
		munmap(img->base, img->dim);
	img->base = NULL;
}

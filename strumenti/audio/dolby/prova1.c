/* Compito 1: il codice originale del DLL dell'altoparlante gira su Linux.
 *   ./prova1 <cartella dei DLL> <elenco delle impronte> */
#include "indirizzi.h"
#include "pe.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
	char p[1100], cmd[2300];
	pe_t img;
	uint32_t mem, scr;

	if (argc != 3)
		return 1;
	snprintf(p, sizeof(p), "%s/DolbyAPOvlldp150.dll", argv[1]);
	if (pe_carica(&img, p, argv[2]))
		return 2;
	mem = win_chiama(pe_ind(&img, VLLDP_QUERY_MEMORY), 256, 48000, 2, 0, 0);
	scr = win_chiama(pe_ind(&img, VLLDP_QUERY_SCRATCH), 256, 48000, 2, 0, 0);
	printf("memoria dello stato: %u byte; memoria di lavoro: %u byte\n", mem, scr);
	assert(mem >= 4096 && mem <= 64u << 20);
	assert(scr >= 2 * (256 * 4 + 0x27) && scr <= 64u << 20);
	pe_scarica(&img);
	/* un file con un byte diverso deve essere rifiutato senza essere mappato */
	snprintf(cmd, sizeof(cmd), "cp '%s' /tmp/prova1-alterato.dll && printf 'X' | dd of=/tmp/prova1-alterato.dll bs=1 seek=4096 conv=notrunc 2>/dev/null", p);
	assert(system(cmd) == 0);
	assert(pe_carica(&img, "/tmp/prova1-alterato.dll", argv[2]) == -2 && img.base == NULL);
	remove("/tmp/prova1-alterato.dll");
	puts("OK");
	return 0;
}

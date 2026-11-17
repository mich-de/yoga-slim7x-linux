/* Libreria dell'altoparlante (dap_vlldp 1.5) dentro DolbyAPOvlldp150.dll: 48 kHz, 2 canali, blocchi da 256. */
#ifndef VLLDP_H
#define VLLDP_H
#include "pe.h"
#define VLLDP_BLOCCO 256
typedef struct vlldp vlldp_t;
vlldp_t *vlldp_apri(pe_t *img);
void vlldp_elabora(vlldp_t *v, float *const in[2], float *const out[2]);	/* un blocco, canali separati */
uint8_t *vlldp_stato(vlldp_t *v);
/* chiama una funzione della libreria: fn(stato, a1, a2) */
uint64_t vlldp_chiama(vlldp_t *v, uint64_t va, uint64_t a1, uint64_t a2);
void vlldp_chiudi(vlldp_t *v);
#endif

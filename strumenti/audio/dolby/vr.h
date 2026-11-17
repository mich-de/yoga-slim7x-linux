/* Libreria dei contenuti (dap_vr) dentro DolbyAPOVR.dll: 48 kHz, 2 canali, blocchi da 256. */
#ifndef VR_H
#define VR_H
#include "pe.h"
typedef struct vr vr_t;
vr_t *vr_apri(pe_t *img);
uint64_t vr_chiama(vr_t *v, uint64_t va, uint64_t a1, uint64_t a2, uint64_t a3);	/* fn(stato, a1, a2, a3) */
void vr_elabora(vr_t *v, float *const in[2], float *const out[2]);			/* un blocco da 256 */
void vr_chiudi(vr_t *v);
#endif

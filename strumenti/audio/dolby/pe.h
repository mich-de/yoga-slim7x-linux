/* Carica in memoria un DLL di Windows per ARM64 cosi' com'e' (il file non viene modificato) e chiama per
 * indirizzo le funzioni che contiene. Mappatura e rilocazioni adattate da sp11_vlldp_pe_loader.h del progetto
 * geocausa/SP11X1e-audio (licenza BSD-2-Clause). */
#ifndef PE_H
#define PE_H
#include <stddef.h>
#include <stdint.h>
typedef struct { uint8_t *base; size_t dim; uint64_t base_prevista; } pe_t;
/* 0 = mappato; -1 file illeggibile o non PE ARM64; -2 impronta SHA-256 non presente nell'elenco */
int pe_carica(pe_t *img, const char *percorso, const char *elenco_impronte);
void *pe_ind(const pe_t *img, uint64_t va);
void pe_scarica(pe_t *img);
/* Collega le funzioni di Windows importate dal DLL: quelle dell'elenco alle nostre, tutte le altre a una
 * trappola che stampa il nome e ferma il programma. E' il normale lavoro di un caricatore: scrive solo la
 * tabella degli indirizzi importati, non il codice. */
typedef struct { const char *nome; void *fn; } pe_import_t;
int pe_collega(pe_t *img, const pe_import_t *noti, int n);
/* Chiama fn(a0..a4) con x18 puntato a un blocco fittizio: il codice di Windows legge li' il limite dello stack */
uint64_t win_chiama(void *fn, uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4);
/* fn(a0, a1, a2, 0, 0, 0, 0, 0, e quattro zeri sullo stack) */
uint64_t win_chiama_zeri(void *fn, uint64_t a0, uint64_t a1, uint64_t a2);
#endif

# Audio Yoga, motore a file: make; i DLL Dolby si passano come percorso, non stanno nel repository
CFLAGS = -O2 -Wall -ffixed-x18
all: prova1 prova2 prova3 audio_yoga.so prova_plugin
prova1: prova1.c pe.c pe.h indirizzi.h
	$(CC) $(CFLAGS) -o $@ prova1.c pe.c
prova2: prova2.c vlldp.c vlldp.h pe.c pe.h indirizzi.h
	$(CC) $(CFLAGS) -o $@ prova2.c vlldp.c pe.c -lm
prova3: prova3.c vlldp.c vlldp.h pe.c pe.h indirizzi.h
	$(CC) $(CFLAGS) -o $@ prova3.c vlldp.c pe.c -lm
MOTORE = motore.c vlldp.c vr.c pe.c
audio_yoga.so: audio_yoga_ladspa.c $(MOTORE) motore.h vlldp.h vr.h pe.h indirizzi.h
	$(CC) $(CFLAGS) -fPIC -shared -o $@ audio_yoga_ladspa.c $(MOTORE) -lm
prova_plugin: prova_plugin.c
	$(CC) -O2 -Wall -o $@ prova_plugin.c -lm
clean:
	rm -f prova1 prova2 prova3 esplora4 esplora5 esplora_vr esplora_vr2 prova_plugin audio_yoga.so

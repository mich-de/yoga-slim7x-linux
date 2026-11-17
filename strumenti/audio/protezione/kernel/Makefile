# snd-q6apm con protezione altoparlanti, costruito fuori albero ACCANTO a quello di serie:
# nomi di modulo diversi e simboli esportati con prefisso sp_ (snd_q6apm di serie resta caricato
# perche' lo usa q6prm, che non si puo' scaricare senza smontare clock e SoundWire).
# Uso: make [BUILD=cartella]   poi: sudo bash scambia.sh on cartella/src
# Serve kernel-devel della versione in uso, gcc, make, curl, patch.
KREL  ?= $(shell uname -r)
KVER  ?= $(firstword $(subst -, ,$(KREL)))
KDIR  ?= /usr/src/kernels/$(KREL)
BUILD ?= /tmp/q6apm-sp-$(KREL)
QUI   := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
URL   := https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain
Q6    := q6apm.c audioreach.c topology.c q6apm-dai.c q6apm-lpass-dais.c audioreach.h q6apm.h \
         q6dsp-lpass-ports.h q6dsp-common.h q6dsp-errno.h

all: $(BUILD)/src/Kbuild
	$(MAKE) -C $(KDIR) M=$(BUILD)/src modules
	@ls -l $(BUILD)/src/*.ko

# Sorgenti della versione esatta del kernel (riscaricati ogni volta, cosi' la patch parte sempre
# da file puliti), poi la patch, poi l'elenco dei simboli esportati da rinominare.
$(BUILD)/src/Kbuild: $(QUI)q6apm-sp.patch $(QUI)Makefile $(QUI)gprport.c $(QUI)wsavi.c
	mkdir -p $(BUILD)/src
	cd $(BUILD)/src && for f in $(Q6); do curl -fsS --retry 3 -o $$f "$(URL)/sound/soc/qcom/qdsp6/$$f?h=v$(KVER)" || exit 1; done
	curl -fsS --retry 3 -o $(BUILD)/common.h "$(URL)/sound/soc/qcom/common.h?h=v$(KVER)"
	cd $(BUILD) && patch -p0 < $(QUI)q6apm-sp.patch
	cp $(QUI)gprport.c $(QUI)wsavi.c $(BUILD)/src/
	cd $(BUILD)/src && sed -n 's/^EXPORT_SYMBOL\(_GPL\)\?(\(.*\));/#define \2 sp_\2/p' q6apm.c audioreach.c topology.c > rename.h
	printf '%s\n' 'ccflags-y := -include $$(src)/rename.h' \
	  'snd-q6apm-sp-y := q6apm.o audioreach.o topology.o' \
	  'q6apm-dai-sp-y := q6apm-dai.o' \
	  'q6apm-lpass-dais-sp-y := q6apm-lpass-dais.o' \
	  'obj-m := snd-q6apm-sp.o q6apm-dai-sp.o q6apm-lpass-dais-sp.o gprport.o wsavi.o' > $@

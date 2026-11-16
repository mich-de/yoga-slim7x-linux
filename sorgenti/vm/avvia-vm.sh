#!/bin/bash
# Prepara l'immagine di prova (NON la chiavetta) e avvia Fedora in QEMU. Da eseguire come root in WSL.
# uso: avvia-vm.sh [indice voce GRUB, predefinito 3] [secondi massimi, predefinito 3300]
W=/mnt/c/Users/michde/AppData/Local/Temp/claude/ceb2a9da788c7297/c1eee643-a32f-44d4-ae0f-4aa2528891f0/scratchpad
IMG=/mnt/d/linux/_vm/stick.img
VOCE=${1:-0}; MAXS=${2:-3300}
ESP_OFF=3508396032; KIT_OFF=3539992576
mkdir -p /tmp/esp /tmp/kitp
mount -o loop,offset=$ESP_OFF,sizelimit=31457280 "$IMG" /tmp/esp || { echo "mount ESP fallito"; exit 1; }
G=/tmp/esp/EFI/BOOT/grub.cfg
python3 "$W/mk_cpio.py" "$W/kit/initrd" "$W/kit/boot/strumenti.cpio" | tail -n 1; cp "$W/kit/boot/strumenti.cpio" "$W/kit/strumenti/boot/strumenti.cpio"; cp "$W/kit/boot/strumenti.cpio" /tmp/esp/strumenti.cpio; cp "$W/kit/boot/grub.cfg" "$W/kit/strumenti/boot/grub.cfg"
cp "$W/kit/boot/grub.cfg" "$G"      # riparte sempre dal menu vero della chiavetta
sed -i -e "s/^set default=\"0\"/set default=\"$VOCE\"/" -e 's/^set timeout=15/set timeout=3/' -e 's/ quiet rhgb / console=ttyAMA0 /' "$G"
grep -nE '^set (default|timeout)=' "$G"
umount /tmp/esp
mount -o loop,offset=$KIT_OFF,sizelimit=4294967296 "$IMG" /tmp/kitp || { echo "mount STRUMENTI fallito"; exit 1; }
cp -r "$W/kit/strumenti/." /tmp/kitp/                      # kit aggiornato dallo staging
cp "$W/vm/prova-vm.sh" /tmp/kitp/avvio/prova-vm.sh
grep -q prova-vm /tmp/kitp/avvio/autorun-root.sh || printf '%s\n' '[ -f "$KIT/avvio/prova-vm.sh" ] && bash "$KIT/avvio/prova-vm.sh"' >> /tmp/kitp/avvio/autorun-root.sh
rm -rf /tmp/kitp/log/*
sync; umount /tmp/kitp
cp /usr/share/AAVMF/AAVMF_VARS.fd /tmp/vars.fd
echo "avvio QEMU $(date +%H:%M:%S)"
timeout "$MAXS" qemu-system-aarch64 -M virt -cpu neoverse-n1 -smp 8 -m 6G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd \
  -drive if=pflash,format=raw,file=/tmp/vars.fd \
  -drive if=none,id=d0,file="$IMG",format=raw,cache=unsafe -device virtio-blk-device,drive=d0 \
  -device virtio-rng-device -nic none \
  -display none -monitor none -serial file:"$W/vm/seriale.log"
echo "QEMU terminato rc=$? $(date +%H:%M:%S)"
mount -o loop,ro,offset=$KIT_OFF,sizelimit=4294967296 "$IMG" /tmp/kitp && { ls -la /tmp/kitp/log; rm -rf "$W/vm/log"; mkdir -p "$W/vm/log"; cp /tmp/kitp/log/* "$W/vm/log/" 2>/dev/null; umount /tmp/kitp; }

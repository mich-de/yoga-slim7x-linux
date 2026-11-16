#!/bin/bash
# Il kernel della ISO Fedora ha i driver della camera (CAMSS X1E, sensori OV)? Sola lettura.
ISO=/mnt/d/linux/Fedora-KDE-Desktop-Live-45-1.4.aarch64.iso
I=/mnt/yiso; R=/mnt/yroot; mkdir -p $I $R
mountpoint -q $I || mount -o loop,ro "$ISO" $I || exit 1
IMG=$(ls $I/LiveOS/*.img | head -1); echo "immagine: $IMG ($(file -b "$IMG" | cut -c1-50))"
mountpoint -q $R || mount -o loop,ro "$IMG" $R 2>/dev/null || erofsfuse "$IMG" $R 2>/dev/null || { echo "montaggio rootfs fallito"; umount $I; exit 1; }
K=$(ls $R/usr/lib/modules | head -1); M=$R/usr/lib/modules/$K; echo "kernel: $K"
echo '--- moduli camera presenti'
find $M -iname '*camss*' -o -iname 'ov02c10*' -o -iname 'ov02e10*' -o -iname '*qcom-cci*' -o -iname '*qcom_cci*' -o -iname 'ov08x40*' | sed "s|$M/||" | head -12
C=$(find $M -iname 'qcom-camss.ko*' | head -1)
if [ -n "$C" ]; then echo '--- SoC supportati da qcom-camss'; xz -dc "$C" 2>/dev/null | strings | grep -oE 'qcom,[a-z0-9]+-camss' | sort -u | tr '\n' ' '; echo; fi
echo '--- configurazione del kernel'; grep -E 'CONFIG_VIDEO_(QCOM_CAMSS|OV02C10|OV02E10)|CONFIG_I2C_QCOM_CCI|CONFIG_CLK_X1E80100_CAMCC' $M/config 2>/dev/null
echo '--- libcamera e pipeline'; ls $R/usr/lib64 | grep -iE '^libcamera' | head -4; ls $R/usr/lib64/libcamera 2>/dev/null | head -8
echo '--- device tree di altri X1E nello stesso kernel con camera'; grep -l -a 'ovti,ov02' $M/dtb/qcom/x1e*.dtb $M/dtb/qcom/x1p*.dtb 2>/dev/null | xargs -n1 basename 2>/dev/null | head -12
umount $R 2>/dev/null || fusermount -u $R 2>/dev/null; umount $I

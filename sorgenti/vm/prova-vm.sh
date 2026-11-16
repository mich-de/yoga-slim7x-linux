#!/bin/bash
# SOLO nell'immagine di prova (macchina virtuale): esegue gli script del kit su Fedora 45 vera e poi spegne.
KIT=$(dirname "$(dirname "$(readlink -f "$0")")")
R="$KIT/log/prova-vm.txt"
{
echo "=== prova VM $(date) kernel $(uname -r)"
echo "cmdline: $(cat /proc/cmdline)"
echo "getenforce: $(getenforce 2>&1)"
echo "strumenti.service: $(systemctl is-active strumenti.service) / $(systemctl is-enabled strumenti.service 2>&1)"
echo "--- file iniettati dall'initrd aggiuntivo"
ls -la /usr/local/bin/strumenti-* /etc/systemd/system/strumenti.service /etc/systemd/system/multi-user.target.d/ /etc/xdg/autostart/yoga-audio.desktop /usr/share/applications/strumenti-menu.desktop /usr/share/anaconda/post-scripts/ 2>&1
echo "--- audio automatico nella live (file installati da audio-sistema.sh)"
ls -la /usr/lib64/ladspa/ /etc/pipewire/filter-chain.conf.d/ /etc/wireplumber/wireplumber.conf.d/ /etc/systemd/user/default.target.d/ /run/yoga-audio-pronto 2>&1
cat "$KIT/log/autorun.log" 2>&1 | tail -n 25
echo "--- comandi usati dagli script"
for c in python3 kdialog konsole dolphin kwriteconfig6 qdbus6 qdbus gtk-launch kioclient wpctl pw-play pw-cli speaker-test amixer aplay grubby dracut restorecon mokutil rtcwake blkid lsblk gpioset xxd od awk strings pesign dnf rpm tar curl sudo journalctl libinput lsusb kernel-install timeout install lsinitrd chroot tee; do printf '%-16s %s\n' "$c" "$(command -v $c 2>/dev/null || echo MANCA)"; done
echo "--- utente live"; id liveuser 2>&1; grep -rs liveuser /etc/sudoers /etc/sudoers.d 2>&1 | head -n 3
echo "--- patcher"
K=/run/initramfs/live/boot/aarch64/loader/linux
python3 "$KIT/tools/patch-dtb-i2c100k.py" "$K" --check 2>&1
python3 "$KIT/tools/patch-dtb-i2c100k.py" /boot/vmlinuz-$(uname -r) --check 2>&1
echo "--- 8-INSTALLA-FIRMWARE --forza (live)"
bash "$KIT/8-INSTALLA-FIRMWARE.sh" --auto --forza 2>&1 | tail -n 8
echo "--- 9-SECURE-BOOT-STATO"; bash "$KIT/9-SECURE-BOOT-STATO.sh" --auto 2>&1 | tail -n 8
echo "--- 12 senza argomenti nella live (deve rifiutare)"; bash "$KIT/12-TASTIERA-FIX-PERMANENTE.sh" --auto 2>&1 | tail -n 2
echo "--- 10 nella live (deve rifiutare)"; bash "$KIT/10-DOPO-INSTALLAZIONE-FEDORA.sh" --auto 2>&1 | tail -n 2
echo "--- sintassi di tutti gli script con la bash di Fedora"; for f in "$KIT"/*.sh "$KIT"/avvio/*.sh "$KIT"/lib/*.sh; do bash -n "$f" || echo "KO $f"; done; echo fatto
echo "=== DOPO-ANACONDA su una copia sovrapposta del sistema (chroot vero: grubby, dracut, restorecon)"
mkdir -p /tmp/ov/u /tmp/ov/w /tmp/ov/r
if mount -t overlay overlay -o lowerdir=/,upperdir=/tmp/ov/u,workdir=/tmp/ov/w /tmp/ov/r; then
    for m in proc sys dev run; do mount --rbind /$m /tmp/ov/r/$m; done
    echo "kernel in /boot prima: $(python3 "$KIT/tools/patch-dtb-i2c100k.py" /tmp/ov/r/boot/vmlinuz-$(uname -r) --check 2>&1 | tail -n1)"
    YOGA_SALTA_DRACUT=1 bash "$KIT/avvio/dopo-anaconda.sh" /tmp/ov/r 2>&1 | tail -n 45
    T=/tmp/ov/r
    echo "--- verifiche sul sistema 'installato'"
    cmp "$T/boot/vmlinuz-$(uname -r)" "$KIT/boot/linux-7.2.11-300.fc45-kbd100k.efi" && echo "OK kernel in /boot identico al kernel corretto del kit"
    python3 "$KIT/tools/patch-dtb-i2c100k.py" "$T/boot/dtb-$(uname -r)/qcom/x1e80100-lenovo-yoga-slim7x.dtb" --check 2>&1 | tail -n1
    ls -la "$T/etc/kernel/install.d/" "$T/usr/local/sbin/yoga-patch-dtb-i2c100k" "$T/etc/systemd/system/yoga-audio-ampli.service" "$T/etc/systemd/system/multi-user.target.d/" "$T/etc/xdg/autostart/yoga-audio.desktop" "$T/etc/systemd/user/default.target.d/" "$T/etc/modules-load.d/scmi-cpufreq.conf" "$T/etc/dracut.conf.d/qcom-x1e-firmware.conf" 2>&1
    ls -Z "$T/opt/yoga-slim7x" 2>&1 | head -n 8
    ls "$T/usr/lib/firmware/updates/qcom/x1e80100/LENOVO/83ED/" 2>&1 | tr '\n' ' '; echo
    echo "firmware nell'initramfs rigenerato: $(lsinitrd "$T/boot/initramfs-$(uname -r).img" 2>/dev/null | grep -c 'qcom/x1e80100/LENOVO/83ED')"
    chroot "$T" systemd-analyze verify /etc/systemd/system/yoga-audio-ampli.service 2>&1 | head -n 5; echo "verifica unit: rc=$?"
    echo "--- aggancio per i kernel futuri: rimetto il kernel originale e simulo l'installazione di un kernel"
    cp "$K" "$T/boot/vmlinuz-$(uname -r)"
    chroot "$T" /etc/kernel/install.d/99-yoga-kbd100k.install add "$(uname -r)" /boot /boot/vmlinuz-"$(uname -r)" 2>&1 | tail -n 3
    cmp "$T/boot/vmlinuz-$(uname -r)" "$KIT/boot/linux-7.2.11-300.fc45-kbd100k.efi" && echo "OK l'aggancio ha corretto il kernel"
    echo "--- servizio amplificatori nel sistema installato (senza scheda audio deve uscire pulito)"
    timeout 200 chroot "$T" /bin/bash /opt/yoga-slim7x/avvio/audio-ampli.sh 2>&1 | tail -n 3
else
    echo "overlay non montabile: prova dopo-anaconda saltata"
fi
echo "--- 11-AUDIO-BASE nella live (senza hardware audio: deve arrivare in fondo)"; timeout 240 bash "$KIT/11-AUDIO-BASE-FEDORA.sh" --auto 2>&1 | tail -n 14; echo "rc=$?"
echo "--- unit fallite"; systemctl --failed --no-legend 2>&1 | head -n 8
echo "=== fine prova $(date)"
} > "$R" 2>&1
sync
systemctl poweroff

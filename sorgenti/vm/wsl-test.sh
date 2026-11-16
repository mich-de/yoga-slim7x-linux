#!/bin/bash
# Collaudo del kit in WSL (root): sintassi, cpio, simulazione dell'hook di dracut, funzioni, esecuzioni di prova.
W=/mnt/c/Users/michde/AppData/Local/Temp/claude/ceb2a9da788c7297/c1eee643-a32f-44d4-ae0f-4aa2528891f0/scratchpad
K=$W/kit
fail=0
t() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

echo "== 1. sintassi"
for f in $(find "$K/strumenti" -name '*.sh'); do bash -n "$f" || { echo "FAIL bash -n $f"; fail=1; }; done
for f in "$K"/initrd/updates/usr/local/bin/*; do dash -n "$f" || { echo "FAIL dash -n $f"; fail=1; }; done
echo "script controllati: $(find "$K/strumenti" -name '*.sh' | wc -l) + 2 bootstrap"
t "nessun CRLF negli script" "! grep -rlI \$'\r' '$K/strumenti' --include='*.sh' '$K/initrd' '$K/boot/grub.cfg' | grep -q ."

echo "== 2. cpio"
python3 "$W/mk_cpio.py" "$K/initrd" "$K/boot/strumenti.cpio" || fail=1
cp "$K/boot/strumenti.cpio" "$K/strumenti/boot/strumenti.cpio"
python3 "$W/initrd_ls.py" "$K/boot/strumenti.cpio" | head -n 3

echo "== 3. simulazione hook 20-apply-live-updates.sh"
rm -rf /tmp/sim; mkdir -p /tmp/sim/x /tmp/sim/newroot/etc/systemd/system /tmp/sim/newroot/usr/local/bin /tmp/sim/newroot/run
python3 - "$K/boot/strumenti.cpio" /tmp/sim/x <<'PY'
import sys, os
buf = open(sys.argv[1], 'rb').read(); out = sys.argv[2]; p = 0
while buf[p:p+6] == b'070701':
    f = [int(buf[p+6+8*i:p+14+8*i], 16) for i in range(13)]
    mode, fsize, nsize = f[1], f[6], f[11]
    name = buf[p+110:p+110+nsize-1].decode(); d = (p+110+nsize+3) & ~3; body = buf[d:d+fsize]; p = (d+fsize+3) & ~3
    if name == 'TRAILER!!!': break
    dst = os.path.join(out, name)
    if mode & 0o170000 == 0o040000: os.makedirs(dst, exist_ok=True)
    elif mode & 0o170000 == 0o120000: os.makedirs(os.path.dirname(dst), exist_ok=True); os.symlink(body.decode(), dst)
    else:
        os.makedirs(os.path.dirname(dst), exist_ok=True); open(dst, 'wb').write(body); os.chmod(dst, mode & 0o7777)
PY
NEWROOT=/tmp/sim/newroot
( cd /tmp/sim/x/updates && find . -depth -type d -exec mkdir -p "$NEWROOT/{}" \; && find . -depth \! -type d -exec cp -a "{}" "$NEWROOT/{}" \; )
( cd $NEWROOT && find . \( -type f -o -type l \) -printf '%M %p -> %l\n' | sort -k2 )
t "unit presente"            "[ -f $NEWROOT/etc/systemd/system/strumenti.service ]"
t "symlink wants valido"     "[ -L $NEWROOT/etc/systemd/system/multi-user.target.wants/strumenti.service ] && [ -e $NEWROOT/etc/systemd/system/multi-user.target.wants/strumenti.service ]"
t "bootstrap eseguibile"     "[ -x $NEWROOT/usr/local/bin/strumenti-mount ] && [ -x $NEWROOT/usr/local/bin/strumenti-menu ]"
t "autostart presente"       "[ -f $NEWROOT/etc/xdg/autostart/strumenti-menu.desktop ]"
command -v systemd-analyze >/dev/null && { systemd-analyze verify $NEWROOT/etc/systemd/system/strumenti.service 2>&1 | grep -v 'strumenti-mount' | head -n 5; echo "systemd-analyze verify: fatto"; }
command -v desktop-file-validate >/dev/null && desktop-file-validate $NEWROOT/etc/xdg/autostart/strumenti-menu.desktop && echo "desktop file valido"

echo "== 4. funzioni di lib/comune.sh"
rm -rf /tmp/kit; cp -r "$K/strumenti" /tmp/kit
cat > /tmp/dev.txt <<'EOF'
I: Bus=0019 Vendor=0000 Product=0000 Version=0000
N: Name="gpio-keys"
H: Handlers=kbd event0

I: Bus=0018 Vendor=04f3 Product=3212 Version=0100
N: Name="hid-over-i2c 04F3:3212 Touchpad"
H: Handlers=mouse0 event3

I: Bus=0018 Vendor=048d Product=8987 Version=0100
N: Name="hid-over-i2c 048D:8987 Keyboard"
H: Handlers=sysrq kbd leds event5

I: Bus=0018 Vendor=048d Product=8987 Version=0100
N: Name="hid-over-i2c 048D:8987 Consumer Control"
H: Handlers=kbd event6
EOF
cat > /tmp/irq.txt <<'EOF'
 88:        100          5          0   msmgpio   3 Level     hid-over-i2c
 89:         40          2          0   msmgpio  67 Level     hid-over-i2c
 90:          7          0          0   msmgpio  51 Level     hid-over-i2c
 91:          9          9          9   GICv3    17 Level     arch_timer
EOF
cat > /tmp/t-lib.sh <<'EOF'
. /tmp/kit/lib/comune.sh
echo "KIT=$KIT AUTO=$AUTO"
echo "kbd_event=$(kbd_event /tmp/dev.txt)"
echo "irq=$(irq_hid /tmp/irq.txt | irq_somma)"
echo "logdir=$(logdir)"
echo "utente=$(utente)"
stato_tastiera
EOF
cp /tmp/t-lib.sh /tmp/kit/t-lib.sh
out=$(bash /tmp/kit/t-lib.sh --auto 2>&1); echo "$out"
t "kbd_event trova event5"   "echo \"\$out\" | grep -q 'kbd_event=/dev/input/event5'"
t "irq_somma"                "echo \"\$out\" | grep -q 'irq=3=105,67=42,51=7'"
t "KIT e AUTO"               "echo \"\$out\" | grep -q 'KIT=/tmp/kit AUTO=1'"
rm -f /tmp/kit/t-lib.sh

echo "== 5. esecuzioni di prova (WSL non e' il portatile: quasi tutto risultera' KO, conta che lo script arrivi in fondo)"
bash /tmp/kit/1-DIAGNOSTICA.sh --auto > /tmp/diag.out 2>&1; rc=$?
t "1-DIAGNOSTICA termina (rc=$rc)" "[ $rc -eq 0 ]"
t "riepilogo creato"         "ls /tmp/kit/log/riepilogo-*.txt >/dev/null"
t "diag creato"              "ls /tmp/kit/log/diag-*.txt >/dev/null"
grep -c '^\[' /tmp/kit/log/riepilogo-*.txt | sed 's/^/righe OK\/KO: /'
grep -iE 'syntax error|command not found|unexpected|unbound' /tmp/diag.out /tmp/kit/log/riepilogo-*.txt | head -n 5
sed -n '1,12p' /tmp/kit/log/riepilogo-*.txt
bash /tmp/kit/8-INSTALLA-FIRMWARE.sh --auto > /tmp/fw.out 2>&1; rc=$?
t "8 rifiuta un modello diverso (rc=$rc)" "[ $rc -eq 1 ] && grep -q 'Modello rilevato' /tmp/fw.out"
mkdir -p /tmp/fakeroot/usr/lib/firmware
PREFISSO=/tmp/fakeroot bash /tmp/kit/8-INSTALLA-FIRMWARE.sh --auto --forza > /tmp/fw2.out 2>&1; rc=$?
t "8 con PREFISSO installa (rc=$rc)" "[ $rc -eq 0 ] && [ -f /tmp/fakeroot/usr/lib/firmware/updates/qcom/x1e80100/LENOVO/83ED/qcadsp8380.mbn ]"
t "8 crea link topologia"    "[ -L /tmp/fakeroot/usr/lib/firmware/updates/qcom/x1e80100/X1E80100-LENOVO-Yoga-Slim7x-tplg.bin ] && [ -e /tmp/fakeroot/usr/lib/firmware/updates/qcom/x1e80100/X1E80100-LENOVO-Yoga-Slim7x-tplg.bin ]"
t "8 non tocca initramfs con PREFISSO" "grep -q 'rigenera l.initramfs dal sistema' /tmp/fw2.out"
ls /tmp/fakeroot/usr/lib/firmware/updates/qcom/x1e80100/LENOVO/83ED | tr '\n' ' '; echo
( cd /tmp/kit/firmware && sha256sum -c SHA256SUMS --quiet && echo "PASS SHA256SUMS" ) || { echo "FAIL SHA256SUMS"; fail=1; }
t "ucm tarball contiene Slim7x" "tar -tzf /tmp/kit/ucm/alsa-ucm-conf-master.tar.gz | grep -q 'ucm2/Qualcomm/x1e80100/Slim7x-HiFi.conf'"
echo "== 6. correzione tastiera permanente su una radice finta"
ORIG=$W/web/efi/linux.efi
rm -rf /tmp/fr; mkdir -p /tmp/fr/boot /tmp/fr/etc /tmp/fr/usr/lib/modules/7.2.11-300.fc45.aarch64/dtb/qcom
cp "$ORIG" /tmp/fr/boot/vmlinuz-7.2.11-300.fc45.aarch64
cp "$ORIG" /tmp/fr/boot/vmlinuz-0-rescue-0123456789abcdef
cp "$K/dtb/x1e80100-lenovo-yoga-slim7x.dtb" /tmp/fr/usr/lib/modules/7.2.11-300.fc45.aarch64/dtb/qcom/
bash /tmp/kit/12-TASTIERA-FIX-PERMANENTE.sh --auto --sistema /tmp/fr > /tmp/k12.out 2>&1; rc=$?
t "12 termina (rc=$rc)"              "[ $rc -eq 0 ]"
t "12 kernel corretto = kernel del kit" "cmp -s /tmp/fr/boot/vmlinuz-7.2.11-300.fc45.aarch64 /tmp/kit/boot/linux-7.2.11-300.fc45-kbd100k.efi"
t "12 kernel rescue intatto"         "cmp -s /tmp/fr/boot/vmlinuz-0-rescue-0123456789abcdef '$ORIG'"
t "12 dtb separato corretto"         "cmp -s /tmp/fr/usr/lib/modules/7.2.11-300.fc45.aarch64/dtb/qcom/x1e80100-lenovo-yoga-slim7x.dtb '$W/esp-copy/EFI__BOOT__yoga7x-kbd100k.dtb'"
t "12 nessun .orig rimasto"          "! ls /tmp/fr/boot/*.orig 2>/dev/null | grep -q ."
t "12 aggancio e patcher installati" "[ -x /tmp/fr/etc/kernel/install.d/99-yoga-kbd100k.install ] && [ -x /tmp/fr/usr/local/sbin/yoga-patch-dtb-i2c100k ] && sh -n /tmp/fr/etc/kernel/install.d/99-yoga-kbd100k.install"
bash /tmp/kit/12-TASTIERA-FIX-PERMANENTE.sh --auto --sistema /tmp/fr > /tmp/k12b.out 2>&1
t "12 ripetibile (seconda esecuzione senza modifiche)" "grep -q 'Nulla da fare' /tmp/k12b.out && cmp -s /tmp/fr/boot/vmlinuz-7.2.11-300.fc45.aarch64 /tmp/kit/boot/linux-7.2.11-300.fc45-kbd100k.efi"
grep -E 'rc=|aggancio' /tmp/k12.out | cut -c1-150
t "kernel del kit: sha256 annotato"  "sha256sum /tmp/kit/boot/linux-7.2.11-300.fc45-kbd100k.efi | cut -c1-64 | tee /tmp/ksha"
t "script dell'altra sessione non presenti nello staging (non vengono toccati)" "! ls /tmp/kit/5-FIX-TASTIERA-SUBITO.sh /tmp/kit/6-AUDIO-PIU-FORTE.sh /tmp/kit/7-VOLUME-AMPLIFICATORI.sh 2>/dev/null | grep -q ."
echo "== esito complessivo: $([ $fail -eq 0 ] && echo TUTTO OK || echo CI SONO FAIL)"

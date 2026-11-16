#!/bin/bash
# Diagnostica hardware del Lenovo Yoga Slim 7x sotto Linux (qualsiasi distro).
# Crea log/riepilogo-*.txt ([OK]/[KO] per componente) e log/diag-*.txt (dettagli).
# Uso:  bash 1-DIAGNOSTICA.sh        (con --auto non apre finestre)
. "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
apri_terminale "$@"
diventa_root "$@"

LD=$(logdir); T=$(ts)
S="$LD/riepilogo-$T.txt"; O="$LD/diag-$T.txt"
FW=/sys/firmware/devicetree/base
ok() { echo "[OK] $1" >> "$S"; }
ko() { echo "[KO] $1" >> "$S"; }
chk() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else ko "$1"; fi; }
fwfile() { ls /lib/firmware/$1 /lib/firmware/$1.xz /lib/firmware/$1.zst /lib/firmware/updates/$1 /lib/firmware/updates/$1.xz /lib/firmware/updates/$1.zst 2>/dev/null | head -n1; }
P=qcom/x1e80100/LENOVO/83ED

{
echo "Riepilogo hardware - $(modello) - kernel $(uname -r) - $(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")"
echo "cmdline: $(cat /proc/cmdline)"
echo
} > "$S"

chk "Device tree: Lenovo Yoga Slim 7x"          "tr -d '\0' < $FW/compatible | grep -q yoga-slim7x"
echo "--- Tastiera / puntamento (funzionano solo con il bus I2C b80000 a 100 kHz)" >> "$S"
I2CF="$FW/soc@0/geniqup@bc0000/i2c@b80000/clock-frequency"
chk "Bus I2C di tastiera e touchpad a 100 kHz (correzione attiva)" "[ \"\$(od -An -tx1 '$I2CF' | tr -d ' \n')\" = 000186a0 ]"
chk "Bus I2C senza blocchi (nessun errore -110)" "! dmesg | grep -qE 'i2c_hid_of [0-9]+-00(3a|2c): (failed to change power|.*-110)'"
chk "Tastiera: dispositivo I2C 0x3a presente"   "[ -n \"\$(kbd_i2c)\" ]"
chk "Tastiera: driver I2C agganciato"           "[ -L \"\$(kbd_i2c)/driver\" ]"
chk "Tastiera: dispositivo HID creato"          "[ -n \"\$(kbd_hid)\" ]"
chk "Tastiera: driver HID agganciato ($(kbd_hid_driver 2>/dev/null || echo nessuno))" "[ -n \"\$(kbd_hid_driver)\" ]"
chk "Tastiera: dispositivo di input"            "[ -n \"\$(kbd_event)\" ]"
chk "Touchpad"                                  "grep -qi 'touchpad' /proc/bus/input/devices"
chk "Touchscreen"                               "grep -qiE 'touchscreen|04F3|IDEA' /proc/bus/input/devices"
echo "--- Grafica" >> "$S"
chk "GPU Adreno (render node)"                  "ls /dev/dri/renderD*"
chk "GPU: firmware caricato senza errori"       "! dmesg | grep -qiE 'failed to load .*(sqe|gmu|zap)|zap.*fail'"
chk "Retroilluminazione schermo"                "ls /sys/class/backlight/*"
echo "--- Rete" >> "$S"
chk "Wi-Fi (interfaccia wl*)"                   "ls /sys/class/net/ | grep -q '^wl'"
chk "Bluetooth (hci0)"                          "ls /sys/class/bluetooth/hci0"
echo "--- Audio / batteria (dipendono dal coprocessore ADSP)" >> "$S"
chk "Firmware ADSP presente"                   "[ -n \"\$(fwfile $P/qcadsp8380.mbn)\" ]"
chk "Firmware ADSP dtb presente"                "[ -n \"\$(fwfile $P/adsp_dtbs.elf)\" ]"
chk "ADSP in esecuzione"                        "grep -lqx running \$(grep -lE 'adsp|6800000' /sys/class/remoteproc/*/name | sed 's/name\$/state/')"
chk "Topologia audio presente"                  "[ -n \"\$(fwfile qcom/x1e80100/X1E80100-LENOVO-Yoga-Slim7x-tplg.bin)\$(fwfile $P/X1E80100-LENOVO-Yoga-Slim7x-tplg.bin)\" ]"
chk "Profilo ALSA UCM Slim 7x presente"         "ls /usr/share/alsa/ucm2/Qualcomm/x1e80100/Slim7x-HiFi.conf"
chk "Scheda audio rilevata"                     "grep -q '^ *[0-9]' /proc/asound/cards"
chk "Audio: uscita 'Altoparlanti potenziati' attiva (6-AUDIO-PIU-FORTE)" "come_utente wpctl status | grep -q 'Altoparlanti potenziati'"
chk "Audio: modulo guadagno amplificatori caricato (7-VOLUME-AMPLIFICATORI)" "lsmod | grep -q '^wsagain'"
chk "Coprocessore CDSP in esecuzione"           "grep -lqx running \$(grep -lE 'cdsp|32300000' /sys/class/remoteproc/*/name | sed 's/name\$/state/')"
chk "Batteria"                                  "ls /sys/class/power_supply/ | grep -qi bat"
echo "--- Altro" >> "$S"
chk "Webcam (/dev/video*)"                      "ls /dev/video*"
chk "CPU frequency scaling"                     "ls /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
chk "Sensori termici"                           "ls /sys/class/thermal/thermal_zone0"
chk "Sospensione disponibile"                   "grep -q . /sys/power/mem_sleep"
chk "TPM"                                       "ls /dev/tpm0"
chk "Variabili EFI accessibili"                 "ls /sys/firmware/efi/efivars/SecureBoot-*"
chk "Nessuna unit systemd fallita"              "[ -z \"\$(systemctl --failed --no-legend)\" ]"
{
echo
for r in /sys/class/remoteproc/remoteproc*; do
    [ -d "$r" ] && echo "[--] remoteproc $(cat "$r/name" 2>/dev/null): $(cat "$r/state" 2>/dev/null) (fw: $(cat "$r/firmware" 2>/dev/null))"
done
echo; echo "== Tastiera: stato"; stato_tastiera
echo; echo "== Firmware mancanti"
dmesg | grep -iE 'firmware.*fail|failed to load|request_firmware|Direct firmware load' | sed 's/^\[[^]]*\] //' | sort -u
echo; echo "== Unit systemd fallite"; systemctl --failed --no-legend 2>&1
echo; echo "== Errori dei driver"
dmesg | grep -iE 'probe.*fail|failed with error|error -[0-9]+' | sed 's/^\[[^]]*\] //' | sort -u | head -n 60
} >> "$S"

{
echo "== model"; modello; echo
echo "== compatible"; tr '\0' ' ' < $FW/compatible; echo
echo "== uname"; uname -a
echo "== os-release"; cat /etc/os-release 2>/dev/null
echo "== cmdline"; cat /proc/cmdline
echo "== tastiera"; stato_tastiera; irq_hid
echo "== input devices"; cat /proc/bus/input/devices
echo "== switch (capabilities/sw)"; for d in /sys/class/input/input*; do s=$(cat "$d/capabilities/sw" 2>/dev/null); [ -n "$s" ] && [ "$s" != 0 ] && echo "$(cat "$d/name"): sw=$s"; done
echo "== dt nodes keyboard/touchpad/touchscreen/embedded-controller"
find $FW \( -name 'keyboard@*' -o -name 'touchpad@*' -o -name 'touchscreen@*' -o -name 'embedded-controller@*' \) 2>/dev/null | while read -r n; do
    echo "$n: status=$(tr -d '\0' < "$n/status" 2>/dev/null || echo okay) compatible=$(tr '\0' ' ' < "$n/compatible" 2>/dev/null)"
done
echo "== gpio-reserved-ranges"; od -An -tx1 "$(find $FW -name gpio-reserved-ranges | head -n1)" 2>/dev/null
echo "== i2c devices"
for d in /sys/bus/i2c/devices/*; do
    echo "$d name=$(cat "$d/name" 2>/dev/null) driver=$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)"
done
echo "== hid devices"
for d in /sys/bus/hid/devices/*; do echo "$d driver=$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)"; done
echo "== dmesg hid/i2c/lenovo"; dmesg | grep -iE 'hid|i2c|048d|lenovo|0-003a|gpio.?6[5-7]'
echo "== libinput"; libinput list-devices 2>&1 | head -n 120
echo "== gpio debug (65-67)"; mount -t debugfs none /sys/kernel/debug 2>/dev/null; grep -E 'gpio6[5-7] ' /sys/kernel/debug/gpio 2>&1 | head
echo "== net"; ip -br link 2>&1; rfkill list 2>&1
echo "== sound cards"; cat /proc/asound/cards 2>&1; aplay -l 2>&1 | head -n 30
echo "== audio utente"; come_utente wpctl status 2>&1 | head -n 60
echo "== firmware qcom 83ED"; ls -la /lib/firmware/$P /lib/firmware/updates/$P 2>&1
echo "== topologia"; ls -la /lib/firmware/qcom/x1e80100/*Slim7x* /lib/firmware/updates/qcom/x1e80100/*Slim7x* 2>&1
echo "== ucm"; ls /usr/share/alsa/ucm2/Qualcomm/x1e80100/ 2>&1
echo "== pacchetti"; rpm -q kernel-core linux-firmware qcom-firmware alsa-ucm pipewire wireplumber alsa-sof-firmware 2>&1 || dpkg -l linux-firmware alsa-ucm-conf pipewire wireplumber 2>&1 | tail -n 5
echo "== modprobe.d"; grep -rs . /etc/modprobe.d /run/modprobe.d 2>/dev/null
echo "== power_supply"; for p in /sys/class/power_supply/*; do echo "$p: $(cat "$p/type" 2>/dev/null) $(cat "$p/status" 2>/dev/null) $(cat "$p/capacity" 2>/dev/null)"; done
echo "== backlight"; ls -l /sys/class/backlight/ 2>&1
echo "== drm"; ls /sys/class/drm/ 2>&1
echo "== remoteproc"; for r in /sys/class/remoteproc/*; do echo "$r $(cat "$r/name" 2>/dev/null) $(cat "$r/state" 2>/dev/null) fw=$(cat "$r/firmware" 2>/dev/null)"; done
echo "== usb"; lsusb 2>&1
echo "== block"; lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT 2>&1
echo "== efi secure boot"; mokutil --sb-state 2>&1; ls /sys/firmware/efi/efivars 2>/dev/null | grep -cE '^(PK|KEK|db|dbx)-'
echo "== deferred probes"; cat /sys/kernel/debug/devices_deferred 2>&1
echo "== systemctl --failed"; systemctl --failed --no-pager 2>&1
echo "== lsmod"; lsmod
echo "== dmesg"; dmesg
echo "== journal warnings"; journalctl -b -p warning --no-pager 2>/dev/null | tail -n 400
} > "$O" 2>&1
sync
echo; cat "$S"; echo
echo "Log salvati in: $LD"
[ "$AUTO" = 1 ] || popup "Diagnostica completata: log salvati sulla chiavetta" 6

#!/bin/bash
# Prova del ritorno V/I degli amplificatori: calibrazione del DSP con wsavi.ko. Non tocca guadagni.
#   sudo bash prova-vi.sh [chmask [parametri di wsavi, es. isense=1 vsense=-1]]   chmask = canali V/I (predefinito 3)
# Attiva il driver con protezione se serve, suona 30 s di silenzio, 3 s dopo carica wsavi.ko
# (prima gli amplificatori accesi, poi i clock V/I: ordine di Windows) e legge lo stato ogni 2 s.
# Atteso: stato 4 e R0 fra 3,6 e 4,3 ohm. Alla fine toglie wsavi e rimette le tarature normali.
# Il portatile non deve andare in sospensione durante la prova.
set -u
[ "$(id -u)" = 0 ] || { echo "serve root" >&2; exit 1; }
qui=$(cd "$(dirname "$0")" && pwd)
utente=${SUDO_USER:-liveuser}
fw=qcom/x1e80100/LENOVO/83ED
par=/sys/module/snd_q6apm_sp/parameters
cal=yoga-slim7x-spkr-prot-calibrazione.bin
marca="prova-vi $$"

[ -d $par ] || bash "$qui/scambia.sh" on > /dev/null || exit 1
cp "$qui/../$cal" "/lib/firmware/updates/$fw/" && echo -n "$fw/$cal" > $par/sp_cal || exit 1
python3 -c "import wave; w = wave.open('/tmp/silenzio30.wav', 'wb'); w.setparams((2, 2, 48000, 0, 'NONE', '')); w.writeframes(bytes(48000 * 4 * 30))"
echo "$marca" > /dev/kmsg
runuser -u "$utente" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$utente")" pw-play /tmp/silenzio30.wav &
sleep 3
insmod "$qui/$(uname -r)/wsavi.ko" chmask="${1:-3}" "${@:2}" || echo "wsavi non caricato: vedi sotto"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
	sleep 2
	echo "0x4121 0x080011f8 64" > $par/getcfg
done
wait
rmmod wsavi 2> /dev/null
echo -n "$fw/yoga-slim7x-spkr-prot.bin" > $par/sp_cal

dmesg | sed -n "/$marca/,\$p" > /tmp/prova-vi.log
grep -v 'q6apm getcfg' /tmp/prova-vi.log | grep -iE 'wsavi|soundwire|swr|sdw|speaker protection|apm|wsa|Oops'
python3 "$qui/statovi.py" < /tmp/prova-vi.log

#!/bin/bash
# Calibrazione del DSP con gli amplificatori al guadagno di Windows (18 dB = PA Volume 29) e SOLO silenzio.
# La taratura di SP_VI presume quel guadagno: sotto circa 6 dB il tono pilota non viene visto (stato 7).
# Unico segnale: il pilota del DSP, 40 Hz a -40 dBFS (circa 0,11 V di picco). Durante la prova il volume di
# PipeWire va al 5 %; alla fine, anche se qualcosa fallisce, tornano PA Volume e tetto di avvio/audio-ampli.sh
# e il volume di prima. Da usare solo con il consenso dell'utente: e' un aumento di guadagno.
#   sudo bash prova-vi-18db.sh [parametri di prova-vi.sh]
set -u
[ "$(id -u)" = 0 ] || { echo "serve root" >&2; exit 1; }
qui=$(cd "$(dirname "$0")" && pwd)
kit=$(cd "$qui/../../.." && pwd)
utente=${SUDO_USER:-liveuser}
come_utente() { runuser -u "$utente" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$utente")" "$@"; }
C=$(awk '/Yoga-Slim7x/ {print $1; exit}' /proc/asound/cards)
[ -n "$C" ] || { echo "scheda audio del Yoga non trovata" >&2; exit 1; }
vol=$(come_utente wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
ripristina() {
	bash "$kit/avvio/audio-ampli.sh"
	come_utente wpctl set-volume @DEFAULT_AUDIO_SINK@ "${vol:-0.4}"
	echo "ripristinati PA Volume, tetto e volume ($vol)"
}
trap ripristina EXIT

come_utente wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05
for i in $(seq 1 15); do	# il guadagno viene letto solo alla ripartenza dell'uscita: deve essere ferma
	grep -qv closed /proc/asound/card"$C"/pcm*p/sub0/status || break
	sleep 2
done
grep -qv closed /proc/asound/card"$C"/pcm*p/sub0/status && { echo "l'uscita e' in uso: fermare ogni suono e riprovare" >&2; exit 1; }
[ -f /run/wsagain.ko ] || cp "$kit/audio/wsagain.ko" /run/wsagain.ko
rmmod wsagain 2>/dev/null
insmod /run/wsagain.ko en=0 cap=29 || exit 1
for n in WooferLeft WooferRight TweeterLeft TweeterRight; do
	id=$(amixer -c "$C" controls | grep "name='$n PA Volume'" | sed -E 's/numid=([0-9]+).*/\1/')
	amixer -q -c "$C" cset numid="$id" 29 || exit 1
done
(sleep 14; echo "registri a meta' prova (34b1 = 05 vuol dire 18 dB, 3021 = 07 e 3020 = 67 sensori di Windows):"
 grep -hE '^(3020|3021|34b1):' /sys/kernel/debug/regmap/sdw:*/registers | tr '\n' ' '; echo) &
bash "$qui/prova-vi.sh" "$@"
wait

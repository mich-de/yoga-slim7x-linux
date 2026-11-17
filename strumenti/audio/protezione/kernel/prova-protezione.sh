#!/bin/bash
# Prova che la protezione termica del DSP interviene, con gli amplificatori a 18 dB come Windows.
# Da usare solo con il consenso dell'utente: e' un aumento di guadagno (segnale di prova a -20 dBFS).
# Tre passate uguali: 16 tratti di tono a 1 kHz, -20 dBFS, sui woofer, misurati ai microfoni (circa 12 s).
#   1) tarature normali (obiettivo di temperatura 90 gradi)          -> livello costante
#   2) obiettivo abbassato (predefinito 30 gradi), con ritorno V/I   -> il DSP deve attenuare (fino a 12 dB)
#   3) obiettivo abbassato, senza ritorno V/I                        -> dice se il controllo usa la misura
# L'obiettivo e' temp_tgt_q6 di ogni altoparlante nel parametro 0x08001532 di SP_RX (parole 78, 88, 98, 108).
# In coda a ogni passata legge le statistiche del DSP (grezze). Alla fine, anche in caso di errore, rimette
# PA Volume, tetto, volume di PipeWire e tarature normali.
#   sudo bash prova-protezione.sh [gradi]
set -u
[ "$(id -u)" = 0 ] || { echo "serve root" >&2; exit 1; }
qui=$(cd "$(dirname "$0")" && pwd)
kit=$(cd "$qui/../../.." && pwd)
gradi=${1:-30}
utente=${SUDO_USER:-liveuser}
come_utente() { runuser -u "$utente" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$utente")" "$@"; }
fw=qcom/x1e80100/LENOVO/83ED
dfw=/lib/firmware/updates/$fw
par=/sys/module/snd_q6apm_sp/parameters
uscita=alsa_output.platform-sound.HiFi__Speaker__sink
C=$(awk '/Yoga-Slim7x/ {print $1; exit}' /proc/asound/cards)
[ -d $par ] && [ -n "$C" ] || { echo "driver con protezione non attivo (scambia.sh on)" >&2; exit 1; }
vol=$(come_utente wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')

aperta() { grep -qv closed /proc/asound/card"$C"/pcm*p/sub0/status; }
aspetta_ferma() { for i in $(seq 1 15); do aperta || return 0; sleep 2; done; echo "l'uscita resta in uso" >&2; return 1; }
ripristina() {
	rmmod wsavi 2>/dev/null
	pkill -u "$utente" -f "pw-play --target $uscita" 2>/dev/null
	echo -n "$fw/yoga-slim7x-spkr-prot.bin" > $par/sp_cal
	rm -f "$dfw/prova-obiettivo.bin"
	bash "$kit/avvio/audio-ampli.sh"
	come_utente wpctl set-volume @DEFAULT_AUDIO_SINK@ "${vol:-0.4}"
	echo "ripristinati PA Volume, tetto, volume ($vol) e tarature normali"
}
trap ripristina EXIT

python3 - "$qui/../yoga-slim7x-spkr-prot.bin" "$dfw/prova-obiettivo.bin" "$gradi" <<'EOF' || exit 1
import struct, sys
b = bytearray(open(sys.argv[1], 'rb').read()); o = fatti = 0
while o < len(b):
    iid, pid, size, err = struct.unpack_from('<4I', b, o)
    if pid == 0x08001532:
        w = struct.unpack_from('<%dI' % (size // 4), b, o + 16)
        assert w[70] == 4 and all(w[78 + 10 * k] == 0x1680 for k in range(4)), w[70:110]   # 4 altoparlanti, 90 gradi
        for k in range(4):
            struct.pack_into('<I', b, o + 16 + 4 * (78 + 10 * k), int(float(sys.argv[3]) * 64))
        fatti += 1
    o += 16 + (size + 7) // 8 * 8
assert o == len(b) and fatti >= 1, (o, len(b), fatti)   # il parametro c'e' due volte: sottografo e tag
open(sys.argv[2], 'wb').write(b)
EOF
python3 -c "import wave; w = wave.open('/tmp/silenzio60.wav', 'wb'); w.setparams((2, 2, 48000, 0, 'NONE', '')); w.writeframes(bytes(48000 * 4 * 60))"

come_utente wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05
aspetta_ferma || exit 1
[ -f /run/wsagain.ko ] || cp "$kit/audio/wsagain.ko" /run/wsagain.ko
rmmod wsagain 2>/dev/null
insmod /run/wsagain.ko en=0 cap=29 || exit 1
for n in WooferLeft WooferRight TweeterLeft TweeterRight; do
	id=$(amixer -c "$C" controls | grep "name='$n PA Volume'" | sed -E 's/numid=([0-9]+).*/\1/')
	amixer -q -c "$C" cset numid="$id" 29 || exit 1
done

passata() {	# $1 = file di taratura, $2 = etichetta, $3 = vi | senza
	local marca="prova-protezione $$ $2" p
	echo -n "$fw/$1" > $par/sp_cal
	aspetta_ferma || return 1
	echo "$marca" > /dev/kmsg
	come_utente pw-play --target $uscita /tmp/silenzio60.wav &	# tiene accesi uscita e amplificatori
	sleep 3
	if [ "$3" = vi ]; then insmod "$qui/$(uname -r)/wsavi.ko" || return 1; fi
	sleep 6		# il DSP misura resistenza e temperatura
	echo "===== $2: 34b1 (05 = 18 dB): $(grep -hE '^34b1:' /sys/kernel/debug/regmap/sdw:*/registers | tr '\n' ' ')"
	come_utente python3 "$kit/tools/misura-audio.py" toni 0,1 1000 "$(printf -- '-20,%.0s' $(seq 1 15))-20" | awk '!/^#/ {printf "%s ", $2} END {print "  (mic0, dB)"}'
	for p in 0x080011ef 0x080011f0 0x080011f1 0x080011f2; do
		echo "0x411a $p 1024" > $par/getcfg 2>/dev/null || echo "  $p: rifiutato dal DSP"
		sleep 0.3
	done
	rmmod wsavi 2>/dev/null
	pkill -u "$utente" -f "pw-play --target $uscita"; wait
	dmesg | sed -n "/$marca/,\$p" > "/tmp/prova-protezione-$2.log"
	grep 'q6apm getcfg' "/tmp/prova-protezione-$2.log" | sed -E 's/^\[[^]]*\] q6apm getcfg: //' | head -40 | cut -c1-80
	if grep -iE 'PA fault|Oops|wsa884x.*(error|fail)' "/tmp/prova-protezione-$2.log"; then
		echo "ANOMALIA: mi fermo" >&2; return 1
	fi
}

passata yoga-slim7x-spkr-prot.bin normale vi || exit 1
passata prova-obiettivo.bin "obiettivo-$gradi" vi || exit 1
passata prova-obiettivo.bin "obiettivo-$gradi-senza-VI" senza || exit 1

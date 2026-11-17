#!/bin/bash
# Prova del plugin dentro PipeWire senza far suonare gli altoparlanti: una seconda istanza con l'uscita su un
# dispositivo finto, un tono in ingresso, registrazione dell'uscita e misura.   bash prova_pipewire.sh <cartella privata>
set -u
qui=$(cd "$(dirname "$0")/.." && pwd)
priv=${1:?cartella privata con DLL, impronte e profili.txt}
t=$(mktemp -d)
pulisci() { kill "${pid:-0}" 2>/dev/null; [ -n "${nullo:-}" ] && pw-cli destroy "$nullo" >/dev/null 2>&1; rm -rf "$t"; }
trap pulisci EXIT
sed -e 's/effect_input.audio_yoga/effect_input.audio_yoga_prova/; s/effect_output.audio_yoga/effect_output.audio_yoga_prova/' \
    -e 's/target.object = "effect_input.yoga_spk_ay"/target.object = "prova_nullo"/' -e 's/"Audio Yoga"/"Audio Yoga prova"/' \
    "$qui/audio-yoga.conf" > "$t/prova.conf"
trova() { pw-cli ls Node 2>/dev/null | awk -v n="node.name = \"$1\"" '/^\tid /{i=$2} index($0, n){print i}' | tr -d ,; }
timeout 5 pw-cli create-node adapter '{ factory.name=support.null-audio-sink node.name=prova_nullo media.class=Audio/Sink object.linger=true audio.position=[FL,FR] }' >/dev/null 2>&1
sleep 1; nullo=$(trova prova_nullo)
[ -n "$nullo" ] || { echo "uscita finta non creata"; exit 1; }
AUDIO_YOGA_DIR="$priv" LADSPA_PATH="$qui" timeout 60 pipewire -c "$t/prova.conf" > "$t/log" 2>&1 < /dev/null &
pid=$!
for i in $(seq 1 30); do id=$(trova effect_input.audio_yoga_prova); [ -n "$id" ] && break; sleep 0.3; done
[ -n "${id:-}" ] || { echo "nodo non comparso"; cat "$t/log"; exit 1; }
python3 - "$t/tono.wav" <<'PY'
import math, struct, sys, wave
w = wave.open(sys.argv[1], 'wb'); w.setparams((2, 2, 48000, 0, 'NONE', ''))
a = 10 ** (-40 / 20)
w.writeframes(b''.join(struct.pack('<hh', *[int(32767 * a * math.sin(2 * math.pi * 234 * i / 48000))] * 2) for i in range(48000 * 3)))
PY
misura() {	# $1 = profilo; stampa il livello del tono registrato all'uscita
	timeout 5 pw-cli set-param "$id" Props "{ params = [ \"dolby:Profilo\" $1 ] }" >/dev/null 2>&1
	timeout 8 pw-record --target prova_nullo -P stream.capture.sink=true --rate 48000 --channels 2 --format f32 "$t/reg.wav" >/dev/null 2>&1 &
	r=$!
	sleep 0.7; timeout 6 pw-play --target effect_input.audio_yoga_prova "$t/tono.wav"; sleep 0.7; kill $r 2>/dev/null; wait $r 2>/dev/null
	python3 - "$t/reg.wav" <<'PY'
import math, struct, sys, wave
w = wave.open(sys.argv[1], 'rb'); n = w.getnframes(); d = struct.unpack('<%df' % (2 * n), w.readframes(n))[::2]
s = d[len(d) // 3: 2 * len(d) // 3]
print('%.1f' % (20 * math.log10(math.sqrt(2 * sum(x * x for x in s) / max(len(s), 1)) + 1e-30)))
PY
}
m=$(misura 2); s=$(misura 5)
echo "tono a 234 Hz, -40 dBFS: profilo Musica $m dB, profilo Spento $s dB"
python3 -c "import sys; m, s = float('$m'), float('$s'); sys.exit(0 if -38 < m < -33 and abs(s + 40) < 0.5 else 1)" && echo OK || { echo "FUORI DAI VALORI ATTESI"; cat "$t/log"; exit 1; }

#!/bin/bash
# Scambia a caldo il driver audio del DSP: quello di serie <-> quello con protezione altoparlanti.
#   sudo bash scambia.sh on  [cartella dei .ko]   driver con protezione + topologia + tarature
#   sudo bash scambia.sh off                      ritorno al driver e alla topologia di serie
#   sudo bash scambia.sh ricarica                 ricopia topologia e tarature e fa rinascere la scheda
#   bash scambia.sh stato
# Non tocca guadagni ne' volumi. Dopo lo scambio la scheda rinasce con i limiti di serie
# (PA Volume 6): per riavere il volume di prima rilanciare avvio/audio-ampli.sh.
# Se qualcosa va storto il rimedio certo e' il riavvio (niente e' permanente).
# Durante lo scambio il portatile non deve andare in sospensione.
set -u
qui=$(cd "$(dirname "$0")" && pwd)
ko=${2:-$qui/$(uname -r)}
fwtplg=/lib/firmware/updates/qcom/x1e80100	# il kernel chiede qcom/<driver>/<modello>-tplg.bin
fwcal=$fwtplg/LENOVO/83ED			# parametro sp_cal di snd-q6apm-sp
tplg=X1E80100-LENOVO-Yoga-Slim7x-tplg.bin
cal=yoga-slim7x-spkr-prot.bin
bl=/etc/modprobe.d/q6apm-sp.conf
card=/sys/bus/platform/drivers/snd-x1e80100
utente=${SUDO_USER:-liveuser}

apm=
for d in /sys/bus/aprbus/devices/*; do
	grep -qs 'qcom,q6apm' "$d/of_node/compatible" && apm=$(basename "$d")
done
drv() { basename "$(readlink "/sys/bus/aprbus/devices/$apm/driver" 2>/dev/null)" 2>/dev/null; }
muori() { echo "ERRORE: $*" >&2; exit 1; }
audio_utente() {	# start|stop dei demoni audio dell'utente
	runuser -u "$utente" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$utente")" \
		systemctl --user "$1" pipewire.socket pipewire-pulse.socket wireplumber.service \
		pipewire.service pipewire-pulse.service filter-chain.service 2>/dev/null
}
stato() {
	echo "servizio APM: $apm -> driver $(drv)"
	lsmod | grep -E '^(snd_q6apm|q6apm)' | awk '{print "  modulo", $1, "usato da", $3, $4}'
	grep -q . /proc/asound/cards 2>/dev/null && cat /proc/asound/cards || echo "  nessuna scheda audio"
	ls -l "$fwtplg/$tplg" "$fwcal/$cal" 2>/dev/null
}
copia_fw() {
	[ -f "$qui/../topologia/$tplg" ] && [ -f "$qui/../$cal" ] || muori "mancano topologia o tarature"
	mkdir -p "$fwcal" && cp "$qui/../topologia/$tplg" "$fwtplg/" && cp "$qui/../$cal" "$fwcal/" || muori "copia firmware"
}
porta() {	# lo sgancio toglie la porta del servizio dal router GPR e nessuno la rimette: vedi gprport.c
	insmod "$ko/gprport.ko" dev="$apm" && rmmod gprport || muori "porta GPR non ripristinata"
}
scheda_via() {
	audio_utente stop
	sleep 1
	if [ -e "$card/sound" ]; then
		echo sound > "$card/unbind" || muori "la scheda non si stacca"
	fi
}
scheda_su() {
	local i
	for i in 1 2 3 4 5 6 7 8 9 10; do
		[ -e "$card/sound" ] || echo sound > "$card/bind" 2>/dev/null
		grep -q X1E80100 /proc/asound/cards 2>/dev/null && break
		sleep 1
	done
	grep -q X1E80100 /proc/asound/cards 2>/dev/null || { dmesg | tail -30; muori "la scheda audio non e' rinata"; }
	audio_utente start
}

[ -n "$apm" ] || muori "servizio APM del DSP non trovato"
case "${1:-}" in
stato)
	stato ;;
on)
	[ "$(id -u)" = 0 ] || muori "serve root"
	[ "$(drv)" = qcom-apm ] || muori "il driver di serie non e' attivo (stato: $(drv))"
	for f in snd-q6apm-sp.ko q6apm-dai-sp.ko q6apm-lpass-dais-sp.ko gprport.ko; do
		[ -f "$ko/$f" ] || muori "manca $ko/$f (compilare: make -C $qui)"
	done
	copia_fw
	# udev non deve ricaricare i moduli di serie quando rinascono i dispositivi figli
	printf 'blacklist q6apm_dai\nblacklist q6apm_lpass_dais\n' > "$bl"
	scheda_via
	echo "$apm" > /sys/bus/aprbus/drivers/qcom-apm/unbind || muori "il driver di serie non si stacca"
	rmmod q6apm_lpass_dais q6apm_dai || muori "moduli dai di serie ancora in uso"
	porta
	insmod "$ko/snd-q6apm-sp.ko" || muori "insmod snd-q6apm-sp"
	[ "$(drv)" = qcom-apm-sp ] || muori "il driver nuovo non si e' agganciato"
	insmod "$ko/q6apm-dai-sp.ko" && insmod "$ko/q6apm-lpass-dais-sp.ko" || muori "insmod dai"
	scheda_su
	stato
	dmesg | grep -iE 'q6apm|audioreach|speaker protection|qcom-apm' | tail -15 ;;
ricarica)
	[ "$(id -u)" = 0 ] || muori "serve root"
	[ "$(drv)" = qcom-apm-sp ] || muori "il driver con protezione non e' attivo (stato: $(drv))"
	copia_fw
	scheda_via
	scheda_su
	stato ;;
off)
	[ "$(id -u)" = 0 ] || muori "serve root"
	[ "$(drv)" = qcom-apm-sp ] || muori "il driver con protezione non e' attivo (stato: $(drv))"
	scheda_via
	echo "$apm" > /sys/bus/aprbus/drivers/qcom-apm-sp/unbind || muori "il driver non si stacca"
	rmmod q6apm_lpass_dais_sp q6apm_dai_sp snd_q6apm_sp || muori "moduli ancora in uso"
	porta
	rm -f "$bl" "$fwtplg/$tplg" "$fwcal/$cal"
	modprobe q6apm_dai && modprobe q6apm_lpass_dais || muori "moduli di serie"
	echo "$apm" > /sys/bus/aprbus/drivers/qcom-apm/bind || muori "il driver di serie non si riaggancia"
	scheda_su
	stato ;;
*)
	sed -n '2,9p' "$0" ;;
esac

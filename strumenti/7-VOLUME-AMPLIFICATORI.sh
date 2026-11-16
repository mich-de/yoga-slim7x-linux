#!/bin/bash
# Alza il guadagno degli amplificatori degli altoparlanti (WSA884x) oltre il minimo imposto dal kernel:
# woofer PA Volume 18 (circa +4 dB), tweeter 16 (circa +1/+2,5 dB). Tetto fissato a 18.
# ATTENZIONE: in Linux non c'e' la protezione altoparlanti di Windows. Non aumentare questi valori.
# Usare insieme a 6-AUDIO-PIU-FORTE.sh. Solo kernel 7.2.11-300.fc45 (altrimenti ricompilare audio/wsagain.c:
#   dnf install gcc make kernel-devel-$(uname -r); make -C /usr/src/kernels/$(uname -r) M=$PWD modules).
# Se dopo una sospensione il volume torna basso: rilanciare questo script.
# Per tornare all'originale: riavviare (oppure PA Volume a 6 su tutti e quattro).
[ "$(id -u)" = 0 ] || exec sudo bash "$0" "$@"
cd "$(dirname "$0")"
U=${SUDO_USER:-liveuser}; asuser(){ sudo -u "$U" XDG_RUNTIME_DIR=/run/user/$(id -u "$U") "$@"; }
# 1) il volume di sistema non deve comandare gli amplificatori
if ! cmp -s audio/51-yoga-soft-mixer.conf /etc/wireplumber/wireplumber.conf.d/51-yoga-soft-mixer.conf; then
  mkdir -p /etc/wireplumber/wireplumber.conf.d && cp audio/51-yoga-soft-mixer.conf /etc/wireplumber/wireplumber.conf.d/
  asuser systemctl --user restart wireplumber; sleep 6
fi
# 2) tetto del controllo e valori
lsmod | grep -q '^wsagain' && rmmod wsagain
cp audio/wsagain.ko /tmp/ && insmod /tmp/wsagain.ko en=0 cap=18 || { echo "modulo non caricabile su questo kernel"; read -p "Invio" _; exit 1; }
set_pa(){ id=$(amixer -c 0 controls | grep "name='$1 PA Volume'" | sed -E 's/numid=([0-9]+).*/\1/'); [ -n "$id" ] && amixer -q -c 0 cset numid=$id $2 && echo "$1 PA Volume = $2"; }
set_pa WooferLeft 18; set_pa WooferRight 18; set_pa TweeterLeft 16; set_pa TweeterRight 16
# 3) amplificatori sempre accesi: dopo una sospensione del portatile il loro risveglio a ogni pausa
#    si blocca (~30 s di ritardo e altoparlanti muti). Consuma poco di piu' ma l'audio parte subito.
for d in /sys/bus/soundwire/devices/sdw:*; do echo on > $d/power/control; done
[ -t 0 ] && read -p "Fatto. Premi Invio per chiudere" _

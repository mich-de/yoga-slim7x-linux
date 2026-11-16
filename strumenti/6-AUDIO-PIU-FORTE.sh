#!/bin/bash
# Installa l'uscita "Altoparlanti potenziati" (PipeWire filter-chain) e la rende predefinita.
# Da lanciare come utente normale. Per toglierla: systemctl --user disable --now filter-chain
cd "$(dirname "$0")"
rpm -q ladspa-swh-plugins >/dev/null || sudo dnf install -y ladspa-swh-plugins
mkdir -p ~/.config/pipewire/filter-chain.conf.d
cp audio/50-yoga-altoparlanti.conf ~/.config/pipewire/filter-chain.conf.d/
systemctl --user enable filter-chain.service 2>/dev/null
systemctl --user restart filter-chain.service
sleep 2
ID=$(pw-cli ls Node 2>/dev/null | awk '/^\tid /{id=$2} /node.name = "effect_input.yoga_spk"/{print id}' | tr -d ,)
[ -n "$ID" ] && wpctl set-default "$ID"
[ -n "$ID" ] && echo "OK: uscita 'Altoparlanti potenziati' attiva (id $ID)" || { echo "KO"; systemctl --user status filter-chain --no-pager | tail -15; }
[ -t 0 ] && read -p "Premi Invio per chiudere" _

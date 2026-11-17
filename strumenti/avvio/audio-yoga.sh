#!/bin/bash
# Installa SENZA RETE "Audio Yoga": il filtro PipeWire con il codice Dolby dell'altoparlante e l'app dei profili.
#   bash audio-yoga.sh [radice del sistema]     (nessun argomento = sistema in esecuzione)
# File privati (i due DLL Dolby del Windows di questo portatile, impronte, profili): cartella dolby-privato del kit.
# Se un DLL manca lo copia, in sola lettura, dal Windows del portatile. Senza quei file il filtro lascia
# passare l'audio invariato. Il plugin gia' compilato sta in audio/dolby/audio_yoga.so (make in quella cartella).
KIT=$(dirname "$(dirname "$(readlink -f "$0")")")
R=${1:-}
S="$KIT/audio/dolby"
PRIV="$KIT/dolby-privato"
metti() { mkdir -p "$(dirname "$2")" && install -m "${3:-0644}" "$1" "$2" && echo "  $2"; }
echo "audio-yoga: destinazione ${R:-/}"
if [ ! -f "$S/audio_yoga.so" ]; then echo "  plugin non compilato in $S: niente da installare"; exit 0; fi
mkdir -p "$PRIV"
if [ ! -f "$PRIV/DolbyAPOvlldp150.dll" ] || [ ! -f "$PRIV/DolbyAPOVR.dll" ]; then
    for d in /dev/mapper/win-*; do
        [ -e "$d" ] || continue
        m=$(mktemp -d)
        if mount -t ntfs3 -o ro "$d" "$m" 2>/dev/null; then
            for n in DolbyAPOvlldp150.dll DolbyAPOVR.dll; do
                f=$(ls "$m"/Windows/System32/DriverStore/FileRepository/dax3_swc_aposvc_arm64*/"$n" 2>/dev/null | head -n1)
                if [ -n "$f" ] && [ ! -f "$PRIV/$n" ] && cp "$f" "$PRIV/"; then echo "  $n copiato dal Windows del portatile"; fi
            done
            umount "$m"
        fi
        rmdir "$m" 2>/dev/null
    done
fi
[ -f "$PRIV/sha256-dll-yoga.txt" ] || cp "$KIT/audio-auto/dolby/dati/sha256-dll-yoga.txt" "$PRIV/" 2>/dev/null
[ -s "$PRIV/profili.txt" ] || python3 "$S/profili.py" "$KIT/audio-auto/dolby/taratura-yoga.json" > "$PRIV/profili.txt" 2>/dev/null
dir="$PRIV"
if [ -n "$R" ]; then dir=/opt/yoga-slim7x/dolby-privato; mkdir -p "$R$dir" && cp "$PRIV"/* "$R$dir/" 2>/dev/null; fi
metti "$S/audio_yoga.so" "$R/usr/lib64/ladspa/audio_yoga.so" 0755
metti "$S/audio-yoga.conf" "$R/etc/pipewire/audio-yoga.conf"
# Catena degli altoparlanti per Audio Yoga: quella di "Altoparlanti potenziati" senza il compressore (che
# appiattirebbe di nuovo cio' che il motore ha fatto: misurato il 17/11, quattro profili entro 0,4 dB). Resta un
# guadagno fisso di 6 dB (con 12 il segnale era gia' al tetto digitale a volume pieno e le differenze non
# passavano), l'incrocio, la correzione e il limitatore generale a -1,5 dBFS. Il limitatore dei
# bassi a -9 dBFS viene alzato a -1,5: imitava il regolatore Dolby, che ora c'e' davvero a monte (a questo
# guadagno degli amplificatori -1,5 dBFS sono 1,4 V di picco, meno di quanto Windows lascia passare).
mkdir -p "$R/etc/pipewire/filter-chain.conf.d"
sed -e 's/"Altoparlanti potenziati"/"Altoparlanti (via Audio Yoga)"/' \
    -e 's/effect_input\.yoga_spk/effect_input.yoga_spk_ay/; s/effect_output\.yoga_spk/effect_output.yoga_spk_ay/' \
    -e 's/"Ratio (1:n)" = 3.0/"Ratio (1:n)" = 1.0/' -e 's/"Input gain (dB)" = 6.0/"Input gain (dB)" = 0.0/' \
    -e 's/"Limit (dB)" = -9.0/"Limit (dB)" = -1.5/' -e 's/"Makeup gain (dB)" = 12.0/"Makeup gain (dB)" = 6.0/' \
    "$KIT/audio/50-yoga-altoparlanti.conf" > "$R/etc/pipewire/filter-chain.conf.d/52-yoga-altoparlanti-ay.conf" &&
    echo "  $R/etc/pipewire/filter-chain.conf.d/52-yoga-altoparlanti-ay.conf"
metti "$S/audio_yoga.py" "$R/usr/local/bin/audio-yoga" 0755
mkdir -p "$R/etc/systemd/user/default.target.d" "$R/usr/share/applications" "$R/etc/xdg/autostart"
printf '%s\n' '[Unit]' 'Description=Audio Yoga: profili audio con il motore dell altoparlante' \
    'After=pipewire.service filter-chain.service' 'BindsTo=pipewire.service' '' '[Service]' \
    "Environment=AUDIO_YOGA_DIR=$dir" 'ExecStart=/usr/bin/pipewire -c audio-yoga.conf' 'Restart=on-failure' \
    'Slice=session.slice' '' '[Install]' 'WantedBy=default.target' > "$R/etc/systemd/user/audio-yoga.service"
# drop-in invece del collegamento in *.wants (i preset di systemd lo toglierebbero)
printf '%s\n' '[Unit]' 'Wants=audio-yoga.service' > "$R/etc/systemd/user/default.target.d/11-audio-yoga.conf"
printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Audio Yoga' 'Comment=Profili audio del Yoga Slim 7x' \
    'Exec=/usr/local/bin/audio-yoga' 'Icon=audio-card' 'Categories=AudioVideo;Audio;' > "$R/usr/share/applications/audio-yoga.desktop"
printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Audio Yoga' 'Exec=/usr/local/bin/audio-yoga --vassoio' \
    'X-KDE-autostart-phase=2' > "$R/etc/xdg/autostart/audio-yoga.desktop"
echo "  servizio, voce di menu e avvio automatico installati (cartella privata: $dir)"
if [ -z "$R" ] && command -v restorecon >/dev/null; then restorecon -R /usr/lib64/ladspa /etc/pipewire /etc/systemd/user /usr/local/bin 2>/dev/null; fi
exit 0

#!/bin/bash
# Menu grafico degli strumenti: si usa con touchpad o touchscreen, senza tastiera.
# Si apre da solo all'accesso con la voce GRUB "FIX TASTIERA + STRUMENTI"; a mano:  bash avvio/menu-utente.sh
KIT=$(dirname "$(dirname "$(readlink -f "$0")")")
cd "$KIT" || exit 1
root() { konsole --hold -e sudo -E bash "$KIT/$1" $2; }
user() { konsole --hold -e bash "$KIT/$1"; }

if ! command -v kdialog >/dev/null; then
    konsole --hold -e bash -c "cat '$KIT/LEGGIMI.txt'; echo; echo 'Esempio:  sudo bash $KIT/1-DIAGNOSTICA.sh'"
    exit 0
fi

while :; do
    c=$(kdialog --title "Strumenti Yoga Slim 7x" --geometry 780x600 \
        --menu "Scegli cosa fare. I risultati vengono salvati sulla chiavetta (cartella log)." \
        diag   "1 - Diagnostica: cosa funziona e cosa no" \
        kbd    "5 - Tastiera e touchpad: ripara SUBITO (bus I2C a 100 kHz)" \
        aud1   "6 - Audio: uscita 'Altoparlanti potenziati' (tweeter attivi)" \
        aud2   "7 - Audio: guadagno degli amplificatori (leggi le avvertenze)" \
        inst   "Installa Fedora sul disco (programma di installazione)" \
        kbdp   "12 - Dopo l'installazione, PRIMA di riavviare: tastiera permanente sul sistema installato" \
        post   "10 - Sul sistema installato: dopo-installazione completo" \
        audb   "11 - Sul sistema installato: audio di base (se non c'e' la scheda audio)" \
        fw     "8 - Installa i firmware Qualcomm" \
        sb     "9 - Stato del Secure Boot" \
        claude "4 - Claude Code in questa sessione (serve la rete)" \
        vkbd   "Attiva la tastiera virtuale a schermo" \
        files  "Apri la cartella STRUMENTI" \
        esci   "Chiudi questo menu") || break
    case "$c" in
        diag)   root 1-DIAGNOSTICA.sh ;;
        kbd)    root 5-FIX-TASTIERA-SUBITO.sh ;;
        aud1)   user 6-AUDIO-PIU-FORTE.sh ;;
        aud2)   root 7-VOLUME-AMPLIFICATORI.sh ;;
        kbdp)   root 12-TASTIERA-FIX-PERMANENTE.sh --dalla-live ;;
        post)   root 10-DOPO-INSTALLAZIONE-FEDORA.sh ;;
        audb)   root 11-AUDIO-BASE-FEDORA.sh ;;
        fw)     root 8-INSTALLA-FIRMWARE.sh ;;
        sb)     root 9-SECURE-BOOT-STATO.sh ;;
        claude) user 4-CLAUDE-CODE.sh ;;
        files)  dolphin "$KIT" >/dev/null 2>&1 & ;;
        inst)
            d=$(ls /usr/share/applications/*anaconda*.desktop /usr/share/applications/*liveinst*.desktop 2>/dev/null | head -n1)
            if [ -n "$d" ]; then (gtk-launch "$(basename "$d" .desktop)" || kioclient exec "$d") >/dev/null 2>&1 &
            else kdialog --sorry "Programma di installazione non trovato: usa l'icona 'Install to Hard Drive' sul desktop."; fi ;;
        vkbd)
            m=$(ls /usr/share/applications/com.github.maliit.keyboard.desktop /usr/share/applications/*maliit*.desktop 2>/dev/null | head -n1)
            if [ -n "$m" ]; then
                kwriteconfig6 --file kwinrc --group Wayland --key InputMethod "$m"
                kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardEnabled true
                (qdbus6 org.kde.KWin /KWin reconfigure || qdbus org.kde.KWin /KWin reconfigure) >/dev/null 2>&1
                kdialog --msgbox "Tastiera virtuale attivata: tocca un campo di testo per farla comparire."
            else
                kdialog --sorry "Tastiera virtuale (maliit) non installata in questa sessione. Alternativa: tastiera USB o Bluetooth."
            fi ;;
        esci|"") break ;;
    esac
done

# ctl "Nome controllo" [valore]: legge o scrive un controllo ALSA per numid (la ricerca per nome di amixer qui fallisce)
ctl() { local id; id=$(amixer -c0 controls | grep -F "name='$1'" | sed -E 's/numid=([0-9]+).*/\1/'); [ -n "$id" ] || { echo "controllo assente: $1"; return 1; }
  if [ $# -gt 1 ]; then amixer -q -c0 cset numid=$id "$2"; fi; echo "$1 = $(amixer -c0 cget numid=$id | sed -n 's/.*: values=//p')"; }
# reg AMP: campiona DRE_CTL_1 ogni 0,5 s per 6 s (serve root)
reg() { echo | sudo -S -p '' sh -c 'for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf "%s " $(sed -n "s/^34b1: //p" "/sys/kernel/debug/regmap/'"$1"'/registers"); sleep 0.5; done; echo'; }

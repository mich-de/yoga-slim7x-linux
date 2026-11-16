# Yoga Slim 7x: a fine installazione prepara da solo il sistema installato (tastiera, audio, firmware).
# La logica sta sulla partizione STRUMENTI della chiavetta: avvio/dopo-anaconda.sh
%post --nochroot --log=/tmp/yoga-slim7x-post.log
if [ -f /run/strumenti/avvio/dopo-anaconda.sh ]; then
    /bin/bash /run/strumenti/avvio/dopo-anaconda.sh "${ANA_INSTALL_PATH:-/mnt/sysroot}"
fi
exit 0
%end

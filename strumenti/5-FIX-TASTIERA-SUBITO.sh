#!/bin/bash
# Ripara tastiera interna + touchpad SENZA riavviare (se si e' avviato con una voce senza "FIX TASTIERA").
# Porta il bus I2C b80000.i2c da 400 a 100 kHz (modulo fix-tastiera/i2cslow2.ko, solo kernel 7.2.11-300.fc45),
# sblocca la linea SDA e ricarica i driver.
[ "$(id -u)" = 0 ] || exec sudo bash "$0" "$@"
cd "$(dirname "$0")"
command -v gpioset >/dev/null || dnf install -y libgpiod-utils
mount -t debugfs none /sys/kernel/debug 2>/dev/null
CH=$(gpiodetect | awk '/f100000.pinctrl/{print $1}'); DEV=b80000.i2c
N=/sys/firmware/devicetree/base/soc@0/geniqup@bc0000/i2c@b80000/clock-frequency
if [ "$(xxd -p $N)" != 000186a0 ]; then
  cp fix-tastiera/i2cslow2.ko /tmp/ && insmod /tmp/i2cslow2.ko || { echo "modulo non caricabile (kernel diverso da 7.2.11-300.fc45?): ricompilare fix-tastiera/i2cslow2.c"; read -p "Invio" _; exit 1; }
fi
echo 0 > /sys/bus/i2c/drivers_autoprobe
[ -e /sys/bus/platform/devices/$DEV/driver ] && echo $DEV > /sys/bus/platform/drivers/geni_i2c/unbind
sleep 0.5; n=0
while :; do gpioset -c $CH -d open-drain -b pull-up -t 2ms,0 1=0; s=$(gpioget -c $CH -b pull-up --numeric 0); n=$((n+1)); [ $n -ge 10 ] && [ "$s" = 1 ] && break; [ $n -gt 60 ] && break; done
gpioset -c $CH -d open-drain -b pull-up -t 2ms,0 0=0
echo 1 > /sys/bus/i2c/drivers_autoprobe
echo $DEV > /sys/bus/platform/drivers/geni_i2c/bind
sleep 5
grep -E '^N:.*(048D|04F3)' /proc/bus/input/devices && echo "OK: tastiera e touchpad attivi" || echo "KO: vedi dmesg"
read -p "Premi Invio per chiudere" _

#!/bin/bash
# Compila la topologia con protezione altoparlanti. Serve: m4, alsatplg (dnf install alsa-topology-utils), git.
# Uso: build.sh [cartella di audioreach-topology gia' scaricata]   -> X1E80100-LENOVO-Yoga-Slim7x-tplg.bin qui accanto
set -e
qui=$(cd "$(dirname "$0")" && pwd)
src=${1:-${TMPDIR:-/tmp}/audioreach-topology}
[ -d "$src/audioreach" ] || git clone --depth 1 https://github.com/linux-msm/audioreach-topology "$src"
tmp=$(mktemp -d)
m4 -I "$src" -I "$qui" "$qui/X1E80100-LENOVO-Yoga-Slim7x-sp.m4" > "$tmp/sp.conf"
# alsatplg segnala come "undefined" i due widget dei DAI di backend: sono del kernel, e' normale.
alsatplg -c "$tmp/sp.conf" -o "$tmp/sp-tplg.bin" 2>&1 | grep -v 'undefined \(sink\|source\) widget/stream .*_CODEC_DMA_' || true
[ -s "$tmp/sp-tplg.bin" ]
cp "$tmp/sp-tplg.bin" "$qui/X1E80100-LENOVO-Yoga-Slim7x-tplg.bin"
cp "$tmp/sp.conf" "$qui/X1E80100-LENOVO-Yoga-Slim7x-sp.conf"
rm -rf "$tmp"
ls -l "$qui/X1E80100-LENOVO-Yoga-Slim7x-tplg.bin"

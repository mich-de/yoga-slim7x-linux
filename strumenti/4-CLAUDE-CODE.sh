#!/bin/bash
# Installa Claude Code nella sessione Linux corrente (serve la rete) e lo avvia nella cartella degli strumenti.
# NON va eseguito come root. Nella live va rifatto a ogni avvio (la live non conserva nulla).
. "$(dirname "$(readlink -f "$0")")/lib/comune.sh"
apri_terminale "$@"
export PATH="$HOME/.local/bin:$PATH"
if ! command -v claude >/dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash || { echo "Installazione non riuscita: manca la rete?"; exit 1; }
fi
cd "$KIT" || exit 1
exec claude "Leggi HANDOFF.md e LEGGIMI.txt in questa cartella e riprendi da li'. Sei su Linux sul Lenovo Yoga Slim 7x (X Elite)."

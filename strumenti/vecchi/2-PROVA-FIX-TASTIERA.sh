#!/bin/bash
# Nome vecchio: rimanda al nuovo script.
exec bash "$(dirname "$(readlink -f "$0")")/2-TASTIERA-TEST-E-FIX.sh" "$@"

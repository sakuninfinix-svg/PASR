#!/bin/sh
set -eu
WINEPREFIX="${WINEPREFIX:-/home/agus/.mt5}"
export WINEPREFIX
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

app="${1:-}"
case "$app" in
  /*) src="$app" ;;
  *) src="$app" ;;
esac
if [ $# -gt 0 ]; then shift; fi

compiledir="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
METALOG="$compiledir/metaeditor_compile.log"
mkdir -p "$compiledir" >/dev/null 2>&1 || true

if [ -n "$src" ]; then
  : > "$METALOG"
  cmd=( wine "$compiledir/MetaEditor64.exe" "$src" /compile /log )
else
  cmd=( wine "$compiledir/MetaEditor64.exe" )
fi

export WINEESYNC=1
export WINEFSYNC=1
export WINEDEBUG="fixme-all,-err:toolbar,-err:sync"
export WINEDEBUG="${WINEDEBUG:-fixme-all}"
"${cmd[@]}" "$@"
code=$?

exit "$code"

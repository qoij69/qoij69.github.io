#!/bin/sh
# Starts the TuneFetch host (the PC side the phone tweak syncs from).
cd "$(dirname "$0")" || exit 1
command -v python3 >/dev/null 2>&1 || { echo "python3 is missing (sudo apt install python3)"; exit 1; }
python3 -c "import tkinter" 2>/dev/null || { echo "tkinter is missing (sudo apt install python3-tk)"; exit 1; }
[ -f tunefetch.html ] || echo "Note: tunefetch.html is not in this folder. Copy it here to get the web page for adding downloads."
exec python3 tunefetch_host.py

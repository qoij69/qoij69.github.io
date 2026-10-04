# TuneFetch Host (PC side)

Does the downloading (yt-dlp) and sends the finished songs to the iPhone. The TuneFetch app on the iPhone controls it.

## Setup
1. Python 3.9+. On Linux also: `sudo apt install python3-tk`.
2. Start it: `./run_host.sh` (Linux/Mac) or `python tunefetch_host.py` (Windows).
3. Press **Start**. The window shows an **access code**. Press **QR code** and scan it in the app (Settings -> Scan QR code from the host); that fills in the PC's address and the code. (Or type both by hand.)
   Any other phone's camera can scan the same QR code: it opens the web page already signed in.
   yt-dlp, mutagen and ffmpeg are installed automatically on first run (needs internet).
4. If the iPhone cannot connect: `sudo ufw allow 8080/tcp` (the PC only needs port 8080 open; port 8081 is on the iPhone).

The window also shows every iPhone that checked in: its state, how many files were sent and how many are left.
The access code and the save folder are remembered in `.tunefetch-config.json` next to the script. **New code** replaces the code.

## How it works
- The app calls the host on port 8080: `/api/add`, `/api/jobs`, `/api/cancel`, `/api/retry`, `/api/clear`, `/api/ping`. Every call except `/api/ping` needs the access code (header `X-TF-Token`).
  Without the code `/api/ping` only answers `{"ok": true, "auth": false}`.
- The iPhone checks in with `POST /api/device`. The host remembers the iPhone's address and keeps sending for 30 minutes after the last check-in.
- The host sends every finished file that the iPhone does not have yet with `PUT /put/<path>` (plus the access code) to the iPhone on port 8081.
  Files that are still being downloaded or converted are never sent. A file the iPhone refuses is skipped after 3 tries; the others continue.
  What was already sent is stored in `.tunefetch-pushed.json` next to the script.
- The web page (`tunefetch.html`) still works: open it, then Settings -> Access code.

## Security
Only run it on a network you trust. Traffic is plain HTTP; the access code protects against other devices using your host, not against someone sniffing your Wi-Fi.

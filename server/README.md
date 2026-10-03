# TuneFetch Host (PC side)

Does the downloading (yt-dlp) and sends the finished songs to the iPhone. The TuneFetch app on the iPhone controls it.

## Setup
1. Python 3.9+. On Linux also: `sudo apt install python3-tk`.
2. Start it: `./run_host.sh` (Linux/Mac) or `python tunefetch_host.py` (Windows).
3. Press **Start**. The window shows the PC's address. Enter its IP in the app (Settings -> Server).
   yt-dlp, mutagen and ffmpeg are installed automatically on first run (needs internet).
4. If the iPhone cannot connect: `sudo ufw allow 8080/tcp` (the PC only needs port 8080 open; port 8081 is on the iPhone).

## How it works
- The app calls the host on port 8080: `/api/add`, `/api/jobs`, `/api/cancel`, `/api/retry`, `/api/clear`, `/api/ping`.
- The iPhone checks in with `POST /api/device` (every 5 minutes and on "Sync now"). The host remembers the iPhone's address.
- The host then sends every finished file that the iPhone does not have yet with `PUT /put/<path>` to the iPhone on port 8081.
  What was already sent is stored in `.tunefetch-pushed.json` next to the script.
- The old web page (`tunefetch.html`) still works but is no longer needed.

## Security
No login. Only run it on a network you trust.

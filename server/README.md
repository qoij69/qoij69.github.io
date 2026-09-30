# TuneFetch Host (PC side)

The phone tweak syncs from this. It serves the download folder over your local network.

## Setup
1. Python 3.9+. On Linux also: `sudo apt install python3-tk`.
2. Put `tunefetch.html` (the web page for adding downloads) in this folder, next to `tunefetch_host.py`.
3. Start it: `./run_host.sh` (Linux/Mac) or `python tunefetch_host.py` (Windows).
4. Press **Start** in the window. It shows `http://PC_IP:8080/tunefetch.html`.
   yt-dlp, mutagen and ffmpeg are installed automatically on first run (needs internet).
5. On the phone: Settings -> TuneFetch -> Server = `PC_IP` (only the IP, port 8080 is default).

## Notes
- Phone and PC must be on the same Wi-Fi. If the phone cannot connect: `sudo ufw allow 8080/tcp`.
- Downloads go to `~/Music/TuneFetch`. The phone only pulls mp3, m4a, aac, wav and mp4 while
  "Only formats iOS can play" is on, so download as mp3 or m4a.
- The host has no login. Only run it on a network you trust.

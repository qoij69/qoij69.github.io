# TuneFetch

TuneFetch downloads music to a jailbroken iPhone.

- The **host** is a small program on your PC. It downloads songs with yt-dlp.
- The **TuneFetch app** (a normal icon on the iPhone's home screen) is the remote control. You paste links or type song names there, watch the queue, and choose the folder on the iPhone.
- The host **sends every finished song to that folder on the iPhone** over Wi-Fi. A small background service on the iPhone receives the files.

```
 TuneFetch app --- add links, see queue --->  PC host (port 8080)  --- downloads with yt-dlp
 background service  <--- host sends finished songs (port 8081) ---  PC host
```

Requirements: jailbroken iPhone with iOS 6 or later (32-bit armv7 build, tested on iOS 6) with Cydia; a PC with Python 3.9+; both on the same Wi-Fi.

## 1. Install on the iPhone

### Option A: Cydia

1. Install **PreferenceLoader** from Cydia first.
2. Cydia -> Manage -> Sources -> Edit -> Add -> `https://qoij69.github.io/`
3. Open the source, go to Tweaks, install **TuneFetch**.
4. Restart the iPhone (full power off and on). A **TuneFetch** icon appears on the home screen. If it does not, restart SpringBoard or the iPhone once more.

Check beforehand that the iPhone can open `https://qoij69.github.io/Release` in Safari. If Safari shows a certificate error, old iOS cannot use the repo, so use Option B.

### Option B: install the .deb over SSH

You need OpenSSH on the iPhone and its IP address (Settings -> Wi-Fi -> blue arrow). Default root password: `alpine`. On the PC:

```
scp -o HostKeyAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group1-sha1 debs/com.qoij.tunefetch_0.3.0-1+debug_iphoneos-arm.deb root@PHONE_IP:/tmp/
ssh -o HostKeyAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group1-sha1 root@PHONE_IP "dpkg -i /tmp/com.qoij.tunefetch_0.3.0-1+debug_iphoneos-arm.deb"
```

Replace `PHONE_IP`, then restart the iPhone once. (The message `launch_msg(): Socket is not connected` during an SSH install is normal.)

## 2. Start the host on the PC

The host is in the `server/` folder of this repo.

1. Install Python 3.9+. On Linux also run `sudo apt install python3-tk`.
2. Start it: `./server/run_host.sh` (Linux/Mac) or `python server\tunefetch_host.py` (Windows).
3. Press **Start** in the window. It shows the PC's address, for example `http://192.168.178.29:8080/...`. The IP in it is what you enter in the app.
4. On first start the host installs yt-dlp, mutagen and ffmpeg itself (internet needed). Keep the window open while you use TuneFetch.

Downloads are stored on the PC in `~/Music/TuneFetch` (changeable in the host window). If the iPhone cannot connect, allow the port on the PC firewall: `sudo ufw allow 8080/tcp`.

## 3. Set up the app

Open **TuneFetch** on the iPhone, tab **Settings**:

| Setting | What to do |
|---|---|
| Server | The PC's IP address, for example `192.168.178.29`. Port 8080 is added automatically. |
| Test connection | Must show "Connected". |
| Save to | Folder on the iPhone that receives the songs. Default `/var/mobile/Media/music`. It must be inside `/var/mobile/`. |
| Only formats iOS plays | On: the host only sends mp3, m4a, aac, wav and mp4. |
| Wi-Fi only | On: the iPhone only checks in with the host over Wi-Fi. |
| Embed cover art | Puts the thumbnail into mp3/m4a files. |
| Whole playlists | Off: a link downloads one song. On: a playlist link downloads everything. |
| Sync now | Tells the host to send everything that is ready right now. |

The grey text at the bottom shows what the background service is doing, for example "Online: Up to date".

## 4. Download music

Tab **Downloads**: paste links or type song names (one per line), tap **Format** and choose one, then tap **Add to queue**.

| Format | Plays on iOS 6? |
|---|---|
| MP3, M4A (AAC), AAC, WAV | yes |
| MP4 video 720p / 1080p | yes (720p is safer on old devices) |
| FLAC, OPUS, OGG Vorbis, MKV, WEBM | no. With "Only formats iOS plays" on, these are kept on the PC and not sent. Turn that setting off to send them anyway (for example for a player app such as VLC). |
 The list shows progress. Tap a row to cancel or retry. **Clear** removes finished rows. The line at the top shows whether the host is reachable and how many files are on their way to the iPhone.

When a download finishes, the host sends the file to the iPhone automatically within about 20 seconds. The iPhone only needs to be awake on the same Wi-Fi and have checked in with the host in the last 15 minutes (it does this every 5 minutes, and immediately after "Sync now").

## Where do the songs go?

Files are normal files in the folder you set (default `/var/mobile/Media/music`). They do **not** appear in the built-in Music app, which only shows songs registered in its own library database. Open them with a file manager such as iFile, or with an app that plays from a folder, for example VLC.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Can't reach the host" | Host not started (press **Start**), wrong IP, different Wi-Fi, or firewall. Test `http://PC_IP:8080/api/ping` in Safari on the iPhone. |
| Top line says "iPhone has not checked in yet" | The background service is not running. Restart the iPhone. |
| Songs finish on the PC but never arrive | Port 8081 may be blocked on the iPhone side or the host cannot reach the iPhone. The top line shows "Error: ..." with the reason. The "Server" setting in the app must be the PC's IP, because the iPhone only accepts files from that address. |
| Downloaded but not in Music | See "Where do the songs go?". |
| App icon missing | Restart the iPhone, or run `uicache` as user mobile over SSH. |
| Service errors | Look at `/var/tmp/tunefetchd.log` on the iPhone. |

## Build from source

Needs [Theos](https://theos.dev) and a device SDK that supports armv7, such as `iPhoneOS10.3.sdk` from https://github.com/theos/sdks in `$THEOS/sdks`.

```
cd tunefetch-tweak
make clean
make package
```

The `.deb` is created in `packages/`. The many "built for iOS Simulator" linker warnings are harmless.

## Update the repo after a new build

1. Raise `Version:` in `control`, then run `make package`.
2. Put the new `.deb` in `debs/` and delete the old one.
3. Run `python3 make_repo.py https://qoij69.github.io`
4. `git add . && git commit -m "update" && git push`

## Security

- The host has no login. Anyone on your network who knows its address can add downloads and read your download folder.
- When any device registers with the host, the host sends your songs to that device. The iPhone only accepts files from the PC address you entered, and only into a folder inside `/var/mobile/`.
- Only run the host on a network you trust.

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
scp -o HostKeyAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group1-sha1 debs/*.deb root@PHONE_IP:/tmp/tunefetch.deb
ssh -o HostKeyAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group1-sha1 root@PHONE_IP "dpkg -i /tmp/tunefetch.deb"
```

Replace `PHONE_IP`, then restart the iPhone once. (The message `launch_msg(): Socket is not connected` during an SSH install is normal.)

## 2. Start the host on the PC

The host is in the `server/` folder of the [`tunefetch` branch](https://github.com/qoij69/qoij69.github.io/tree/tunefetch) of this repo. Get it with `git clone -b tunefetch https://github.com/qoij69/qoij69.github.io tunefetch`, or open the branch on GitHub and use Code -> Download ZIP. The commands below are run from inside that folder.

1. Install Python 3.9+. On Linux also run `sudo apt install python3-tk`.
2. Start it: `./server/run_host.sh` (Linux/Mac) or `python server\tunefetch_host.py` (Windows).
3. Press **Start** in the window. It shows an **access code** (8 letters and digits). Press **QR code** to show a QR code that holds the PC's address and the code, so you do not have to type anything. You can also type the PC's address (for example `192.168.1.23`) and the code in the app. The code keeps other devices on your network from using your host. **New code** creates a new one.
4. On first start the host installs yt-dlp, mutagen and ffmpeg itself (internet needed). Keep the window open while you use TuneFetch.

Downloads are stored on the PC in `~/Music/TuneFetch` (changeable in the host window). If the iPhone cannot connect, allow the port on the PC firewall: `sudo ufw allow 8080/tcp`.

## 3. Set up the app

Open **TuneFetch** on the iPhone, tab **Settings**:

| Setting | What to do |
|---|---|
| Scan QR code from the host | Opens the camera. Point it at the QR code in the host window (press **QR code** there): Server and Code are filled in and the connection is tested. |
| Server | The PC's IP address, for example `192.168.1.23`. Port 8080 is added automatically. |
| Code | The access code from the host window. |
| Test connection | Must show "Connected". It says so if the host is running but the code is wrong. |
| Save to | Folder on the iPhone that receives the songs. Default `/var/mobile/Media/music`. It must be inside `/var/mobile/`. |
| Only formats iOS plays | On: the host only sends mp3, m4a, aac, wav and mp4. |
| Wi-Fi only | On: the iPhone only checks in with the host over Wi-Fi. |
| Check in every | How often the iPhone tells the host it is online (1 minute to 1 hour). Default 5 minutes. |
| Embed cover art | Puts the thumbnail into mp3/m4a files. |
| Whole playlists | Off: a link downloads one song. On: a playlist link downloads everything. |
| Sync now | Checks in with the host right now and tells you the real answer (for example "The host has 2 file(s) for this iPhone"). |

The grey text at the bottom shows what the background service is doing, for example "Online: Up to date (just now)". If it says "NOT RUNNING", restart the iPhone.

## 4. Download music

Tab **Downloads**: paste links or type song names (one per line), tap **Format** and choose one, then tap **Add to queue**.

| Format | Plays on iOS 6? |
|---|---|
| MP3, M4A (AAC), AAC, WAV | yes |
| MP4 video 720p / 1080p | yes (720p is safer on old devices) |
| FLAC, OPUS, OGG Vorbis, MKV, WEBM | no. With "Only formats iOS plays" on, these are kept on the PC and not sent. Turn that setting off to send them anyway (for example for a player app such as VLC). |
 The list shows progress. Tap a row to cancel or retry. **Clear** removes finished rows. The line at the top shows whether the host is reachable and how many files are on their way to the iPhone.

When a download finishes, the host sends the file to the iPhone automatically within about 20 seconds. The iPhone must be awake on the same Wi-Fi and have checked in with the host in the last 30 minutes. It checks in on its own (every 5 minutes by default, right away when Wi-Fi comes back after sleep, and every 30 seconds while files are on the way) and immediately after "Sync now". A sleeping iPhone switches its Wi-Fi to low power and can miss the host, so unlock it once if a file is slow to arrive; the transfer continues by itself.

## Where do the songs go?

Files are normal files in the folder you set (default `/var/mobile/Media/music`). They do **not** appear in the built-in Music app, which only shows songs registered in its own library database. Open them with a file manager such as iFile, or with an app that plays from a folder, for example VLC.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Can't reach the host" | Host not started (press **Start**), wrong IP, different Wi-Fi, or firewall. Test `http://PC_IP:8080/api/ping` in Safari on the iPhone. The status line names the reason. |
| "Wrong access code" / "refused the access code" | The code in the app (Settings -> Code) must match the one in the host window. If you pressed **New code** on the PC, enter the new one. |
| Top line says "iPhone has not checked in yet" | The background service is not running or the code is missing. Restart the iPhone and check Settings -> Code. |
| Songs finish on the PC but never arrive | The host window shows each iPhone's state, for example "Phone not reachable (asleep?)": unlock the iPhone and wait a moment. Port 8081 must not be blocked on the iPhone side. A single file the iPhone refuses is skipped (after 3 tries) so it does not block the others. |
| Downloaded but not in Music | See "Where do the songs go?". |
| App icon missing | Restart the iPhone, or run `uicache` as user mobile over SSH. |
| Service errors | Look at `/var/mobile/Library/Caches/tunefetchd.log` on the iPhone. |

## Build from source

The source (PC host and iPhone tweak) is in the `tunefetch` branch of this repo. You need [Theos](https://theos.dev) and a device SDK that supports armv7, such as `iPhoneOS10.3.sdk` from https://github.com/theos/sdks in `$THEOS/sdks`.

```
git clone -b tunefetch https://github.com/qoij69/qoij69.github.io tunefetch
cd tunefetch/tweak
make clean
make package FINALPACKAGE=1
```

The `.deb` is created in `packages/`. The many "built for iOS Simulator" linker warnings are harmless.

## Credits

QR scanning in the app uses [quirc](https://github.com/dlbeer/quirc) by Daniel Beer (ISC license, included in the source). The host draws the QR code with [segno](https://pypi.org/project/segno/), which it installs by itself.

## Security

- The web page `tunefetch.html` itself is public (it only contains the page), but everything it does needs the access code (Settings tab on the page).
- The host and the iPhone use a shared **access code**. The host only answers (and only sends songs to) devices that present the code, and the iPhone only accepts files that come with the same code, and only into a folder inside `/var/mobile/`.
- The QR code contains the access code: do not share screenshots of it. Another phone's camera reads the same QR code as a link that opens the web page already signed in.
- The code and your songs travel over plain HTTP on your Wi-Fi, so anyone who can watch your network traffic could read them. Use a network you trust.
- Only run the host on a network you trust.

# TuneFetch

TuneFetch downloads music to a jailbroken iPhone automatically. A small program on your PC (the **host**) downloads songs with yt-dlp. A background service on the phone (the **tweak**) checks the PC every few minutes and copies new songs over Wi-Fi.

- **Phone:** jailbroken iOS 6 or later (32-bit armv7 build, tested on iOS 6), with Cydia
- **PC:** Python 3.9+ on Linux, Windows or Mac
- Phone and PC must be on the same Wi-Fi network

```
 PC (host, port 8080)  <--- Wi-Fi --->  phone (TuneFetch service)
 downloads songs                        copies new songs to /var/mobile/Media/music
```

## 1. Install the tweak on the phone

### Option A: through Cydia (recommended)

1. Install **PreferenceLoader** from Cydia if it is not installed yet (TuneFetch needs it for its Settings page).
2. Cydia -> Manage -> Sources -> Edit -> Add.
3. Enter `https://qoij69.github.io/` and let Cydia refresh.
4. Open the source, go to Tweaks, install **TuneFetch**.
5. Restart the phone once (full power off and on).

Before adding the source, you can check that the phone can reach it: open `https://qoij69.github.io/Release` in Safari on the phone. If Safari shows a certificate error, old iOS versions cannot open the site, so use Option B.

### Option B: install the .deb by hand over SSH

You need OpenSSH on the phone (Cydia) and the phone's IP address (Settings -> Wi-Fi -> blue arrow next to your network). The default root password is `alpine`. Run on the PC:

```
scp -o HostKeyAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group1-sha1 debs/com.qoij.tunefetch_0.2.0-1+debug_iphoneos-arm.deb root@PHONE_IP:/tmp/
ssh -o HostKeyAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group1-sha1 root@PHONE_IP "dpkg -i /tmp/com.qoij.tunefetch_0.2.0-1+debug_iphoneos-arm.deb"
```

Replace `PHONE_IP` with the real address. Then restart the phone once.

## 2. Start the host on the PC

The host is in the `server/` folder of this repo.

1. Install Python 3.9 or newer. On Linux also run `sudo apt install python3-tk`.
2. Put `tunefetch.html` in the `server/` folder, next to `tunefetch_host.py`.
3. Start it:
   - Linux/Mac: `./server/run_host.sh`
   - Windows: `python server\tunefetch_host.py`
4. Press **Start** in the window. It shows an address like `http://192.168.178.29:8080/tunefetch.html`. The number is your **PC's IP address**. Keep the window open while you want syncing.
5. Open that address in the PC's browser to add downloads. On first run the host installs yt-dlp, mutagen and ffmpeg itself (internet needed).

Songs are saved in `~/Music/TuneFetch` on the PC. Download them as **mp3 or m4a**, because the phone only copies formats iOS can play (mp3, m4a, aac, wav, mp4) by default.

If the phone cannot connect, the PC firewall may block port 8080. On Ubuntu: `sudo ufw allow 8080/tcp`.

## 3. Set up the tweak on the phone

Open Settings -> TuneFetch:

| Setting | What to do |
|---|---|
| Server | Your PC's IP address only, for example `192.168.178.29`. Port 8080 is used automatically. To use another port write `192.168.178.29:9000`. |
| Enable sync | On. |
| Check every | How often the phone asks the PC for new songs (1 minute to 1 hour). |
| Wi-Fi only | On keeps it from syncing over mobile data. |
| Only formats iOS can play | On skips flac, opus, ogg and mkv/webm files. |
| Folder | Where songs are saved. Default: `/var/mobile/Media/music`. |

Then tap **Test connection**. "Backend ONLINE" means the phone can reach the host. Tap **Sync now** to start a sync immediately.

The grey text under "Actions" shows the last status, for example "Up to date (0 new)" or "Downloading ...".

## Where do the songs go?

Files are saved as normal files in `/var/mobile/Media/music`. They do **not** appear in the built-in Music app, because that app only shows songs registered in its own library database. Open them with a file manager such as iFile, or with an app that plays from a folder, for example VLC.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Backend OFFLINE" | Check that the host is running and you pressed Start, that the IP is right, and that both devices are on the same Wi-Fi. Open `http://PC_IP:8080/api/ping` in Safari on the phone. If that does not load, the PC firewall is the usual cause. |
| Status never changes, nothing downloads | The background service is not running. Restart the phone. To check over SSH: `launchctl list \| grep -i tunefetch`. |
| "Up to date (0 new)" but files are missing | The host has nothing new in a playable format. On the PC run `curl -s http://127.0.0.1:8080/api/library`. `[]` means no finished files. |
| Songs downloaded but not in Music | See "Where do the songs go?" above. |
| Errors from the service | Look at `/var/tmp/tunefetchd.log` on the phone. |

Installing over SSH prints `launch_msg(): Socket is not connected` on iOS 6. That is expected: the installer then starts the service directly, and launchd starts it on its own at every boot.

## Build from source

Needs [Theos](https://theos.dev) and a device SDK that supports armv7, such as `iPhoneOS10.3.sdk` from https://github.com/theos/sdks, placed in `$THEOS/sdks`.

```
cd tunefetch-tweak
make clean
make package
```

The `.deb` is created in `packages/`. The linker prints many "built for iOS Simulator" warnings; they are harmless.

## Update the repo after a new build

1. Raise `Version:` in `control`, then run `make package`.
2. Put the new `.deb` in `debs/` and delete the old one.
3. Run `python3 make_repo.py https://qoij69.github.io`
4. `git add . && git commit -m "update" && git push`

## Security

The host has no login. Anyone on your network who knows its address can list and download the files in your download folder. Only run it on a network you trust.

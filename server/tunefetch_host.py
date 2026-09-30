#!/usr/bin/env python3
"""TuneFetch Host - run this on the PC. Press Start, then open the shown address on your phone.
Keep tunefetch.html in the same folder. Needs Python 3.9+ (Linux: also python3-tk)."""
import os, re, sys, json, time, socket, shutil, zipfile, tempfile, queue, threading, subprocess, importlib, importlib.util, mimetypes, webbrowser
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse, quote
import tkinter as tk
from tkinter import ttk, filedialog

PORT = 8080
HERE = Path(__file__).resolve().parent
NW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
cfg = {"out": Path.home() / "Music" / "TuneFetch"}
jobs, jlock, jq, logq = [], threading.Lock(), queue.Queue(), queue.Queue()
AUDIO = {"mp3": "mp3", "m4a": "m4a", "opus": "opus", "flac": "flac", "ogg": "vorbis", "wav": "wav", "aac": "aac",
         "best": "best"}
VIDEO = ("mp4", "mkv", "webm")
NAMES = {"title": "%(title)s", "artist": "%(artist,uploader)s - %(title)s", "uploader": "%(uploader)s - %(title)s",
         "id": "%(title)s [%(id)s]"}
STATE = {"ytdlp": None}


def glog(msg):
    logq.put(time.strftime("%H:%M:%S ") + str(msg))


def ensure(mod, pkg):
    if importlib.util.find_spec(mod):
        return
    for extra in ([], ["--user"], ["--user", "--break-system-packages"]):
        r = subprocess.run([sys.executable, "-m", "pip", "install", "-q", pkg] + extra, creationflags=NW)
        if r.returncode == 0:
            break
    importlib.invalidate_caches()
    try:
        import site
        sys.path.append(site.getusersitepackages())
    except Exception:
        pass


_ff = []


def ffmpeg():
    if not _ff:
        p = shutil.which("ffmpeg")
        if not p:
            try:
                ensure("imageio_ffmpeg", "imageio-ffmpeg")
                import imageio_ffmpeg
                p = imageio_ffmpeg.get_ffmpeg_exe()
            except Exception as e:
                glog("ffmpeg unavailable: %s" % e)
        _ff.append(p)
    return _ff[0]


def add_jobs(text, o):
    if o.get("fmt") not in AUDIO and o.get("fmt") not in VIDEO:
        o["fmt"] = "mp3"
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        url = line if line.lower().startswith(("http://", "https://", "ytsearch")) else "ytsearch1:" + line
        with jlock:
            j = {"id": len(jobs) + 1, "url": url, "title": line[:80], "fmt": o["fmt"], "status": "Queued",
                 "pct": 0, "speed": "", "err": "", "files": [], "o": dict(o), "cancel": False}
            jobs.append(j)
        jq.put(j)
        glog("queued: " + line[:80])


def opts_for(job):
    o, fmt, out = job["o"], job["o"]["fmt"], cfg["out"]

    def g(k, d=""):
        return (o.get(k) or d).strip()

    def num(k, d):
        try:
            return float(g(k))
        except ValueError:
            return d

    sub = re.sub(r'[\\/:*?"<>|]', "_", g("folder")).strip(". ")
    parts = [str(out).replace("%", "%%")] + ([sub.replace("%", "%%")] if sub else [])
    if g("plfolder"):
        parts.append("%(playlist_title|)s")
    name = NAMES.get(g("name"), NAMES["title"])
    parts.append(("%(playlist_index&{} - |)s" if g("plnum") else "") + name + ".%(ext)s")
    x = {"outtmpl": os.path.join(*parts), "quiet": True, "no_warnings": True, "ignoreerrors": "only_download",
         "noprogress": True, "noplaylist": g("pl") == "single", "retries": 10,
         "concurrent_fragment_downloads": int(max(1, min(16, num("frag", 4))))}
    f = ffmpeg()
    if f:
        x["ffmpeg_location"] = f
    if num("limit", 0) > 0:
        x["ratelimit"] = num("limit", 0) * 1e6
    if g("proxy"):
        x["proxy"] = g("proxy")
    if g("browser", "none") != "none":
        x["cookiesfrombrowser"] = (g("browser"),)
    if g("archive"):
        x["download_archive"] = str(out / ".tunefetch-archive.txt")
    a, b = g("pstart"), g("pend")
    if a.isdigit() or b.isdigit():
        x["playlist_items"] = "%s:%s" % (a if a.isdigit() else "", b if b.isdigit() else "")
    pps = []
    if g("sb"):
        cats = ["sponsor", "selfpromo", "interaction", "intro", "outro", "music_offtopic"]
        pps += [{"key": "SponsorBlock", "categories": cats, "when": "after_filter"},
                {"key": "ModifyChapters", "remove_sponsor_segments": cats}]
    subs = g("subs", "off")
    if subs != "off":
        x.update(writesubtitles=True, writeautomaticsub=subs == "auto", subtitlesformat="srt/best",
                 subtitleslangs=[t.strip() for t in (g("sublang") or "en").split(",") if t.strip()])
    cover = {"key": "EmbedThumbnail", "already_have_thumbnail": bool(g("keepcover"))}
    if fmt in VIDEO:
        res = g("res")
        h = "[height<=%s]" % res if res.isdigit() else ""
        x["format"] = {"mp4": "bv*%s[ext=mp4]+ba[ext=m4a]/b%s[ext=mp4]/bv*%s+ba/b%s" % (h, h, h, h),
                       "mkv": "bv*%s+ba/b%s" % (h, h),
                       "webm": "bv*%s[ext=webm]+ba[ext=webm]/bv*%s+ba/b%s" % (h, h, h)}[fmt]
        x["merge_output_format"] = fmt
        if subs != "off" and g("embedsubs"):
            pps.append({"key": "FFmpegEmbedSubtitle"})
        if g("meta"):
            pps.append({"key": "FFmpegMetadata"})
        if g("cover") and fmt != "webm":
            x["writethumbnail"] = True
            pps.append(cover)
    else:
        x["format"] = "bestaudio[ext=m4a]/bestaudio/best" if fmt == "m4a" else "bestaudio/best"
        ea, q = {"key": "FFmpegExtractAudio", "preferredcodec": AUDIO[fmt]}, g("aq", "best")
        if fmt in ("mp3", "m4a", "opus", "ogg", "aac"):
            if q != "best":
                ea["preferredquality"] = q
            elif fmt == "mp3":
                ea["preferredquality"] = "0"
        pps.append(ea)
        if g("meta"):
            pps.append({"key": "FFmpegMetadata"})
        if g("cover") and fmt in ("mp3", "m4a", "opus", "flac", "ogg"):
            x["writethumbnail"] = True
            pps.append(cover)
    x["postprocessors"] = pps
    return x


def run(job):
    import yt_dlp

    def ph(d):
        if job.get("cancel"):
            raise yt_dlp.utils.DownloadCancelled()
        if d["status"] == "downloading":
            tot = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
            if tot:
                job["pct"] = int(d.get("downloaded_bytes", 0) * 100 / tot)
            job["speed"] = (d.get("_speed_str") or "").strip()
            info = d.get("info_dict") or {}
            if info.get("title"):
                n = info.get("playlist_index")
                job["title"] = (("%s/%s  " % (n, info.get("n_entries"))) if n else "") + info["title"]
            job["status"] = "Downloading"
        elif d["status"] == "finished":
            job["pct"], job["status"] = 100, "Converting"

    def pph(d):
        if d["status"] == "finished" and d["postprocessor"] == "MoveFiles":
            p = (d.get("info_dict") or {}).get("filepath")
            if p and p not in job["files"]:
                job["files"].append(p)

    o = opts_for(job)
    o["progress_hooks"], o["postprocessor_hooks"] = [ph], [pph]
    job["status"] = "Starting"
    try:
        with yt_dlp.YoutubeDL(o) as y:
            y.download([job["url"]])
        job["status"] = "Canceled" if job["cancel"] else "Done" if job["files"] else "Failed"
        if job["status"] == "Failed":
            job["err"] = "nothing was downloaded (see log)"
    except Exception as e:
        job["status"], job["err"] = ("Canceled", "") if job["cancel"] else ("Failed", str(e)[:200])
    glog("%s: %s %s" % (job["status"], job["title"], job["err"]))


def worker():
    ensure("yt_dlp", "yt-dlp")
    ensure("mutagen", "mutagen")
    import yt_dlp
    STATE["ytdlp"] = yt_dlp.version.__version__
    ffmpeg()
    while True:
        j = jq.get()
        if j["status"] == "Queued":
            run(j)


def snapshot():
    with jlock:
        return [{"id": j["id"], "title": j["title"], "fmt": j["fmt"], "status": j["status"], "pct": j["pct"],
                 "speed": j["speed"], "err": j["err"], "files": [os.path.basename(f) for f in j["files"]]}
                for j in jobs if not j.get("hidden")]


MEDIA = (".mp3", ".m4a", ".aac", ".wav", ".opus", ".flac", ".ogg", ".mp4", ".m4v", ".mkv", ".webm")


def library():
    out, res = cfg["out"], []
    for root, _, fs in os.walk(out):
        for f in fs:
            fp = os.path.join(root, f)
            if f.lower().endswith(MEDIA) and time.time() - os.path.getmtime(fp) > 10:
                res.append({"path": os.path.relpath(fp, out).replace(os.sep, "/"), "size": os.path.getsize(fp)})
    return res


def job_action(kind, jid):
    with jlock:
        sel = [j for j in jobs if jid == "all" or str(j["id"]) == jid]
    for j in sel:
        if kind == "cancel" and j["status"] in ("Queued", "Starting", "Downloading", "Converting"):
            j["cancel"] = True
            if j["status"] == "Queued":
                j["status"] = "Canceled"
        elif kind == "retry" and j["status"] in ("Failed", "Canceled"):
            j.update(status="Queued", pct=0, speed="", err="", files=[], cancel=False)
            jq.put(j)


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, f, *a):
        pass

    def reply(self, code, body=b"", ctype="text/html; charset=utf-8", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, fh, size, name, ctype, inline):
        start, end, code = 0, size - 1, 200
        rg = self.headers.get("Range") or ""
        if rg.startswith("bytes="):
            a, _, b = rg[6:].split(",")[0].partition("-")
            try:
                start = max(0, size - int(b)) if a == "" else int(a)
                end = min(end, int(b)) if (a != "" and b) else end
                code = 206
            except ValueError:
                start, end, code = 0, size - 1, 200
            if code == 206 and (start > end or start >= size):
                return self.reply(416, extra={"Content-Range": "bytes */%d" % size})
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Accept-Ranges", "bytes")
        if code == 206:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.send_header("Content-Disposition", ("inline" if inline else "attachment") + "; filename*=UTF-8''" + quote(name))
        self.end_headers()
        fh.seek(start)
        left = end - start + 1
        while left > 0:
            chunk = fh.read(min(65536, left))
            if not chunk:
                break
            self.wfile.write(chunk)
            left -= len(chunk)

    def do_GET(self):
        u, q = urlparse(self.path), parse_qs(urlparse(self.path).query)
        try:
            if u.path in ("/", "/tunefetch.html", "/tuneftech.html"):
                f = HERE / "tunefetch.html"
                return self.reply(200, f.read_bytes()) if f.exists() else self.reply(404, b"tunefetch.html missing")
            if u.path == "/api/ping":
                with jlock:
                    act = sum(j["status"] in ("Starting", "Downloading", "Converting") for j in jobs)
                    qd = sum(j["status"] == "Queued" for j in jobs)
                info = {"ok": True, "yt_dlp": STATE["ytdlp"], "ffmpeg": (_ff[0] is not None) if _ff else None,
                        "active": act, "queued": qd, "out": str(cfg["out"])}
                return self.reply(200, json.dumps(info).encode(), "application/json")
            if u.path == "/api/jobs":
                return self.reply(200, json.dumps(snapshot()).encode(), "application/json")
            if u.path == "/api/library":
                return self.reply(200, json.dumps(library()).encode(), "application/json")
            if u.path == "/file":
                base = cfg["out"].resolve()
                full = (base / q["p"][0]).resolve()
                if not full.is_relative_to(base) or not full.is_file():
                    return self.reply(404, b"not found")
                with open(full, "rb") as fh:
                    return self.send_file(fh, full.stat().st_size, full.name,
                                          mimetypes.guess_type(str(full))[0] or "application/octet-stream", False)
            if u.path in ("/dl", "/zip"):
                with jlock:
                    j = jobs[int(q["job"][0]) - 1]
                    files = [f for f in j["files"] if os.path.exists(f)]
                if u.path == "/zip":
                    with tempfile.TemporaryFile() as t:
                        with zipfile.ZipFile(t, "w", zipfile.ZIP_STORED) as z:
                            for f in files:
                                z.write(f, os.path.basename(f))
                        return self.send_file(t, t.tell(), "TuneFetch-%d.zip" % j["id"], "application/zip", False)
                p = files[int(q["i"][0])]
                with open(p, "rb") as fh:
                    return self.send_file(fh, os.path.getsize(p), os.path.basename(p),
                                          mimetypes.guess_type(p)[0] or "application/octet-stream", "inline" in q)
            self.reply(404, b"not found")
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            self.reply(400, ("error: %s" % e).encode())

    def do_POST(self):
        n = min(int(self.headers.get("Content-Length") or 0), 1 << 20)
        d = parse_qs(self.rfile.read(n).decode("utf-8", "replace"))
        if self.path == "/api/add":
            add_jobs(d.get("url", [""])[0], {k: v[0] for k, v in d.items() if k != "url"})
        elif self.path in ("/api/cancel", "/api/retry"):
            job_action(self.path[5:], d.get("id", [""])[0])
        elif self.path == "/api/clear":
            with jlock:
                for j in jobs:
                    if j["status"] in ("Done", "Failed"):
                        j["hidden"] = True
        self.reply(303, extra={"Location": "/tunefetch.html"})


def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return socket.gethostbyname(socket.gethostname())


class GUI:
    def __init__(self):
        self.httpd = None
        r = self.r = tk.Tk()
        r.title("TuneFetch Host")
        r.geometry("780x520")
        top = ttk.Frame(r, padding=10)
        top.pack(fill="x")
        self.btn = ttk.Button(top, text="Start", command=self.toggle)
        self.btn.pack(side="left")
        self.addr = tk.StringVar(value="Server stopped - press Start")
        ttk.Entry(top, textvariable=self.addr, state="readonly").pack(side="left", fill="x", expand=True, padx=10)
        fr = ttk.Frame(r, padding=(10, 0))
        fr.pack(fill="x")
        ttk.Label(fr, text="Save to:").pack(side="left")
        self.out = tk.StringVar(value=str(cfg["out"]))
        ttk.Entry(fr, textvariable=self.out).pack(side="left", fill="x", expand=True, padx=6)
        ttk.Button(fr, text="Browse", command=self.browse).pack(side="left")
        ttk.Button(fr, text="Open", command=lambda: self.open_dir()).pack(side="left", padx=4)
        cols = ("id", "title", "fmt", "status", "pct")
        self.tree = ttk.Treeview(r, columns=cols, show="headings", height=12)
        for c, w in zip(cols, (40, 380, 50, 100, 80)):
            self.tree.heading(c, text=c.upper())
            self.tree.column(c, width=w, anchor="w")
        self.tree.pack(fill="both", expand=True, padx=10, pady=10)
        self.logbox = tk.Text(r, height=8, state="disabled")
        self.logbox.pack(fill="x", padx=10, pady=(0, 10))
        r.protocol("WM_DELETE_WINDOW", r.destroy)
        threading.Thread(target=worker, daemon=True).start()
        self.tick()

    def browse(self):
        d = filedialog.askdirectory()
        if d:
            self.out.set(d)

    def open_dir(self):
        p = Path(self.out.get())
        p.mkdir(parents=True, exist_ok=True)
        if os.name == "nt":
            os.startfile(p)
        else:
            subprocess.Popen(["open" if sys.platform == "darwin" else "xdg-open", str(p)])

    def toggle(self):
        if self.httpd:
            self.httpd.shutdown()
            self.httpd.server_close()
            self.httpd = None
            self.btn.config(text="Start")
            self.addr.set("Server stopped - press Start")
            return
        cfg["out"] = Path(self.out.get())
        cfg["out"].mkdir(parents=True, exist_ok=True)
        try:
            self.httpd = ThreadingHTTPServer(("0.0.0.0", PORT), H)
        except OSError as e:
            glog("could not start on port %d: %s" % (PORT, e))
            return
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.btn.config(text="Stop")
        self.addr.set("On your phone open:  http://%s:%d/tunefetch.html" % (lan_ip(), PORT))
        glog("server started")
        webbrowser.open("http://127.0.0.1:%d/tunefetch.html" % PORT)

    def tick(self):
        snap = snapshot()
        live = {str(j["id"]) for j in snap}
        for iid in self.tree.get_children():
            if iid not in live:
                self.tree.delete(iid)
        for j in snap:
            v = (j["id"], j["title"], j["fmt"], j["status"], "%d%%" % j["pct"])
            if self.tree.exists(str(j["id"])):
                self.tree.item(str(j["id"]), values=v)
            else:
                self.tree.insert("", "end", iid=str(j["id"]), values=v)
        try:
            while True:
                m = logq.get_nowait()
                self.logbox.config(state="normal")
                self.logbox.insert("end", m + "\n")
                self.logbox.see("end")
                self.logbox.config(state="disabled")
        except queue.Empty:
            pass
        self.r.after(500, self.tick)


if __name__ == "__main__":
    GUI().r.mainloop()

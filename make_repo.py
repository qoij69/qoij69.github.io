#!/usr/bin/env python3
"""Builds the Cydia repo files (Packages, Packages.bz2, Packages.gz, Release, depictions)
from every .deb in ./debs.   Usage:  python3 make_repo.py https://YOURNAME.github.io"""
import sys, os, re, bz2, gzip, hashlib, subprocess, glob, html

if len(sys.argv) != 2 or not sys.argv[1].startswith("http"):
    sys.exit("usage: python3 make_repo.py https://YOURNAME.github.io")
base = sys.argv[1].rstrip("/")
here = os.path.dirname(os.path.abspath(__file__))
os.chdir(here)
os.makedirs("depictions", exist_ok=True)


def hashes(path):
    d = open(path, "rb").read()
    return len(d), hashlib.md5(d).hexdigest(), hashlib.sha1(d).hexdigest(), hashlib.sha256(d).hexdigest()


def fields(deb):
    out = subprocess.check_output(["dpkg-deb", "-f", deb]).decode("utf-8", "replace")
    return out.rstrip("\n")


entries, latest = [], {}
for deb in sorted(glob.glob("debs/*.deb")):
    ctrl = fields(deb)
    pkg = re.search(r"^Package: (.+)$", ctrl, re.M).group(1).strip()
    ver = re.search(r"^Version: (.+)$", ctrl, re.M).group(1).strip()
    latest[pkg] = (deb, ctrl, ver)          # keep the last (highest sorted) file per package

for pkg, (deb, ctrl, ver) in latest.items():
    size, md5, sha1, sha256 = hashes(deb)
    name = re.search(r"^Name: (.+)$", ctrl, re.M).group(1) if re.search(r"^Name: (.+)$", ctrl, re.M) else pkg
    desc = re.search(r"^Description: (.+)$", ctrl, re.M).group(1) if re.search(r"^Description: (.+)$", ctrl, re.M) else ""
    page = "depictions/%s.html" % pkg
    open(page, "w", encoding="utf-8").write(
        "<!DOCTYPE html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>%s</title><style>body{font-family:-apple-system,Helvetica,sans-serif;margin:16px;color:#222}"
        "h1{font-size:20px}code{background:#eee;padding:1px 4px}</style></head><body>"
        "<h1>%s <small>%s</small></h1><p>%s</p>"
        "<p><b>Setup:</b> Settings &rarr; TuneFetch &rarr; enter your PC's address (e.g. <code>192.168.178.29</code>), "
        "then start <code>tunefetch_host.py</code> on the PC and press Start.</p>"
        "<p><b>Requires:</b> iOS 6.0 or later, PreferenceLoader.</p></body></html>"
        % tuple(html.escape(x) for x in (name, name, ver, desc)))
    entries.append("%s\nFilename: %s\nSize: %d\nMD5sum: %s\nSHA1: %s\nSHA256: %s\nDepiction: %s/%s\n"
                   % (ctrl, deb.replace(os.sep, "/"), size, md5, sha1, sha256, base, page))

packages = "\n".join(entries)
open("Packages", "w", encoding="utf-8").write(packages)
bz2.BZ2File("Packages.bz2", "wb").write(packages.encode("utf-8"))
gzip.GzipFile("Packages.gz", "wb", mtime=0).write(packages.encode("utf-8"))

release = ("Origin: qoij's repo\nLabel: qoij's repo\nSuite: stable\nVersion: 1.0\nCodename: ios\n"
           "Architectures: iphoneos-arm\nComponents: main\nDescription: TuneFetch and other tweaks by qoij\n")
open("Release", "w").write(release)
print("Repo ready: %d package(s). Add %s to Cydia as a source." % (len(entries), base))

# TuneFetch source

- `server/` is the PC host (Python, needs Python 3.9+): `./run_host.sh`
- `tweak/` is the iPhone tweak (Theos project, armv7): `cd tweak && make package FINALPACKAGE=1`

The installable package is in the Cydia source (main branch), see its README.

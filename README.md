# qoij's Cydia repo (GitHub Pages)

1. Build the tweak: `make package` in the tweak folder. Copy the new `.deb` from `packages/` into `debs/`.
2. Run `python3 make_repo.py https://YOURNAME.github.io`
3. Commit and push everything (including `Packages`, `Packages.bz2`, `Packages.gz`, `Release`, `depictions/`, `debs/`).
4. In Settings -> Pages of the GitHub repo, publish from branch `main`, folder `/ (root)`.
5. Add `https://YOURNAME.github.io/` as a source in Cydia.

Repo name must be `YOURNAME.github.io` for the root URL to work.

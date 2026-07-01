# fpp-apt — FPP's Debian apt repository

Signed apt repo served via GitHub Pages at
**https://falconchristmas.github.io/fpp-apt**.

- `pool/` — the `.deb` files (committed; the source of truth). Dependency build
  workflows (e.g. `FalconChristmas/nocc`) push debs here.
- `dists/` — **generated at publish time**, not committed. The `reindex` workflow
  scans `pool/`, signs the metadata, and deploys `pool/` + `dists/` to Pages.
- `.github/workflows/reindex.yml` — runs on any `pool/**` change.

The re-index logic lives in `FalconChristmas/fpp` (`SD/apt-reindex.sh`); this
repo checks FPP out to use it. See `fpp/SD/apt-repo/README.md` for the full
design and one-time setup (signing key, secrets, Pages).

## Install on a device

```
sudo wget -qO /usr/share/keyrings/fpp-archive-keyring.gpg \
    https://falconchristmas.github.io/fpp-apt/fpp-archive-keyring.gpg
sudo tee /etc/apt/sources.list.d/fpp.sources >/dev/null <<'EOF'
Types: deb
URIs: https://falconchristmas.github.io/fpp-apt
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/fpp-archive-keyring.gpg
EOF
sudo apt-get update && sudo apt-get install nocc
```

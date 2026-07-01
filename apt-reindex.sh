#!/bin/bash
#############################################################################
# apt-reindex.sh - Regenerate + sign the FPP apt repo index from its pool.
#
# The FalconChristmas/fpp-apt repository IS the state: pool/ holds every .deb
# (contributed by per-tool build workflows like FalconChristmas/nocc). This
# script scans that pool and (re)writes the dists/ metadata, then GPG-signs it.
# It NEVER rebuilds packages -- adding a dependency is just "drop its .deb into
# pool/, re-run this". Existing packages are untouched.
#
# It's stateless: the committed pool/ is the only source of truth (no aptly DB
# to persist across CI runs). Runs on any Debian/Ubuntu host or GitHub runner
# with apt-utils.
#
# Usage:
#   SD/apt-reindex.sh --repo <fpp-apt checkout> [--dist trixie] \
#       [--component main] [--gpg-key <id>] [--origin FPP] [--label "FPP apt repo"]
#
# With --gpg-key it writes signed InRelease + Release.gpg (required for a real
# repo). Without it, the repo is UNSIGNED (clients need [trusted=yes]); TESTING
# ONLY. In CI the key comes from an fpp-apt Actions secret.
#############################################################################

set -euo pipefail

REPO=""; DIST="trixie"; COMPONENT="main"; GPG_KEY=""
ORIGIN="FPP"; LABEL="FPP apt repo"
while [ $# -gt 0 ]; do
    case "$1" in
        --repo)      REPO="$2"; shift 2 ;;
        --dist)      DIST="$2"; shift 2 ;;
        --component) COMPONENT="$2"; shift 2 ;;
        --gpg-key)   GPG_KEY="$2"; shift 2 ;;
        --origin)    ORIGIN="$2"; shift 2 ;;
        --label)     LABEL="$2"; shift 2 ;;
        -h|--help)   sed -n '2,36p' "$0"; exit 0 ;;
        *) echo "apt-reindex: unknown option: $1" >&2; exit 2 ;;
    esac
done
[ -n "$REPO" ] || { echo "apt-reindex: --repo required" >&2; exit 2; }
REPO="$(readlink -f "$REPO")"
[ -d "$REPO/pool" ] || { echo "apt-reindex: $REPO/pool not found (put .debs under pool/)" >&2; exit 1; }
command -v apt-ftparchive   >/dev/null 2>&1 || { echo "apt-reindex: apt-ftparchive missing (apt-get install apt-utils)" >&2; exit 1; }
command -v dpkg-scanpackages >/dev/null 2>&1 || { echo "apt-reindex: dpkg-scanpackages missing (apt-get install dpkg-dev)" >&2; exit 1; }

# Architectures actually present in the pool (fall back to the standard set).
ARCHES="$(find "$REPO/pool" -name '*.deb' -exec dpkg-deb -f {} Architecture \; 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ *$//')"
[ -n "$ARCHES" ] || ARCHES="armhf arm64 amd64"
echo "==> Re-indexing $REPO  dist=$DIST component=$COMPONENT arches=[$ARCHES]"

# Per-arch Packages index by scanning pool/ (Filename paths come out relative to
# the repo root, e.g. pool/main/n/nocc/...). --multiversion keeps every version
# in the index so older releases stay installable (rollback).
cd "$REPO"
for arch in $ARCHES; do
    d="dists/$DIST/$COMPONENT/binary-$arch"
    mkdir -p "$d"
    dpkg-scanpackages --multiversion --arch "$arch" pool /dev/null > "$d/Packages" 2>/dev/null
    gzip -9kf "$d/Packages"
    echo "  $arch: $(grep -c '^Package:' "$d/Packages" 2>/dev/null || echo 0) package(s)"
done

apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="$ORIGIN" \
    -o APT::FTPArchive::Release::Label="$LABEL" \
    -o APT::FTPArchive::Release::Suite="$DIST" \
    -o APT::FTPArchive::Release::Codename="$DIST" \
    -o APT::FTPArchive::Release::Components="$COMPONENT" \
    -o APT::FTPArchive::Release::Architectures="$ARCHES" \
    release "$REPO/dists/$DIST" > "$REPO/dists/$DIST/Release"

if [ -n "$GPG_KEY" ]; then
    rm -f "$REPO/dists/$DIST/InRelease" "$REPO/dists/$DIST/Release.gpg"
    gpg --batch --yes --local-user "$GPG_KEY" --clearsign \
        -o "$REPO/dists/$DIST/InRelease" "$REPO/dists/$DIST/Release"
    gpg --batch --yes --local-user "$GPG_KEY" --detach-sign --armor \
        -o "$REPO/dists/$DIST/Release.gpg" "$REPO/dists/$DIST/Release"
    echo "==> Signed with GPG key $GPG_KEY"
else
    echo "WARNING: no --gpg-key -> UNSIGNED repo (clients need [trusted=yes]); TESTING ONLY." >&2
fi

touch "$REPO/.nojekyll"   # GitHub Pages: serve dists/ verbatim, no Jekyll
echo "==> Done. Published tree under $REPO (dists/ + pool/)."

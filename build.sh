#!/usr/bin/env bash
# Build a Proton Pass AppImage from Proton's official .deb.
#
# Usage: ./build.sh [VERSION]     (default: latest stable)
# Output: dist/Proton_Pass-<VERSION>-x86_64.AppImage (+ .sha256)
#
# Requires: curl, jq, dpkg-deb, mksquashfs (squashfs-tools, with zstd), sha512sum
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION_JSON_URL="https://proton.me/download/PassDesktop/linux/x64/version.json"
RUNTIME="$ROOT/runtime/runtime-x86_64"
RUNTIME_SHA256="617aa77314d57c8b8e4fae9c3f0b35af7b30d5529cb69e98f64f92510ed98a46"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "$VERSION_JSON_URL" -o "$WORK/version.json"

if [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  VERSION="$(jq -r '[.Releases[] | select(.CategoryName == "Stable") | .Version] | .[]' "$WORK/version.json" | sort -V | tail -n1)"
fi
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "Bad version: $VERSION" >&2; exit 1; }

DEB_ENTRY="$(jq -c --arg v "$VERSION" '.Releases[] | select(.Version == $v) | .File[] | select(.Url | endswith(".deb"))' "$WORK/version.json" | head -n1)"
[[ -n "$DEB_ENTRY" ]] || { echo "No .deb found for version $VERSION" >&2; exit 1; }
DEB_URL="$(jq -r .Url <<<"$DEB_ENTRY")"
DEB_SHA512="$(jq -r .Sha512CheckSum <<<"$DEB_ENTRY")"
[[ "$DEB_URL" == https://proton.me/* ]] || { echo "Unexpected download host: $DEB_URL" >&2; exit 1; }

echo "==> Proton Pass $VERSION"
echo "    $DEB_URL"

# Verify the pinned AppImage runtime
echo "$RUNTIME_SHA256  $RUNTIME" | sha256sum -c --quiet

# Download and verify the official .deb
curl -fsSL "$DEB_URL" -o "$WORK/proton-pass.deb"
echo "$DEB_SHA512  $WORK/proton-pass.deb" | sha512sum -c --quiet
echo "    deb sha512 OK"

# Assemble AppDir
dpkg-deb -x "$WORK/proton-pass.deb" "$WORK/deb"
APPDIR="$WORK/ProtonPass.AppDir"
mkdir -p "$APPDIR/usr"
cp -a "$WORK/deb/usr/lib" "$WORK/deb/usr/share" "$APPDIR/usr/"
install -m 755 "$ROOT/appdir/AppRun" "$APPDIR/AppRun"
cp "$WORK/deb/usr/share/applications/proton-pass.desktop" "$APPDIR/"
echo "X-AppImage-Version=$VERSION" >> "$APPDIR/proton-pass.desktop"
# Upstream ships an SVG under a .png name
cp "$WORK/deb/usr/share/pixmaps/proton-pass.png" "$APPDIR/proton-pass.svg"
ln -s proton-pass.svg "$APPDIR/.DirIcon"

# Pack: runtime + squashfs
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/Proton_Pass-$VERSION-x86_64.AppImage"
mksquashfs "$APPDIR" "$WORK/app.squashfs" -root-owned -noappend -comp zstd -Xcompression-level 19 -b 1M -quiet -no-progress
cat "$RUNTIME" "$WORK/app.squashfs" > "$OUT"
chmod +x "$OUT"
(cd "$ROOT/dist" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")

{
  echo "version=$VERSION"
  echo "deb_url=$DEB_URL"
  echo "deb_sha512=$DEB_SHA512"
  echo "appimage=$OUT"
} > "$ROOT/dist/build-info.txt"

echo "==> Built $OUT"
cat "$OUT.sha256"

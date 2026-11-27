#!/usr/bin/env bash
# Build a Proton Pass AppImage from Proton's official .deb using appimagetool.
#
# Usage: ./build.sh [VERSION]     (default: latest stable)
# Output in dist/:
#   Proton_Pass-<VERSION>-x86_64.AppImage
#   Proton_Pass-<VERSION>-x86_64.AppImage.zsync   (if zsyncmake is installed)
#   Proton_Pass-<VERSION>-x86_64.AppImage.sha256
#   build-info.txt
#
# Requires: curl, jq, gpg, dpkg-deb, sha256sum, sha512sum
# Optional: zsyncmake (zsync), appstreamcli (appstream), desktop-file-validate
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# --- Pinned inputs ---------------------------------------------------------
VERSION_JSON_URL="https://proton.me/download/PassDesktop/linux/x64/version.json"

# appimagetool: tagged release, pinned by SHA-256 (upstream publishes no signature)
APPIMAGETOOL_VERSION="1.9.1"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_VERSION}/appimagetool-x86_64.AppImage"
APPIMAGETOOL_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"

# type2 runtime: latest continuous build, verified by GPG signature
RUNTIME_URL="https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64"
RUNTIME_KEY="$ROOT/keys/type2-runtime.asc"
RUNTIME_KEY_FPR="570C77ACEA40C0F1B758902CBF96CCA56490F695"

APP_ID="io.github.eccl3s.ProtonPass"
REPO="${GITHUB_REPOSITORY:-Eccl3s/proton-pass-appimage}"
UPDATE_INFO="gh-releases-zsync|${REPO%%/*}|${REPO##*/}|latest|Proton_Pass-*-x86_64.AppImage.zsync"
# ---------------------------------------------------------------------------

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
dl() { curl -fsSL --retry 3 -o "$1" "$2"; }

# --- Resolve version -------------------------------------------------------
dl "$WORK/version.json" "$VERSION_JSON_URL"
if [[ $# -ge 1 && -n "$1" ]]; then
  VERSION="$1"
else
  VERSION="$(jq -r '[.Releases[] | select(.CategoryName == "Stable") | .Version] | .[]' "$WORK/version.json" | sort -V | tail -n1)"
fi
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "Bad version: $VERSION" >&2; exit 1; }

REL="$(jq -c --arg v "$VERSION" '[.Releases[] | select(.Version == $v)][0]' "$WORK/version.json")"
[[ "$REL" != "null" ]] || { echo "Version $VERSION not in Proton's feed" >&2; exit 1; }
DEB_URL="$(jq -r '[.File[] | select(.Url | endswith(".deb"))][0].Url' <<<"$REL")"
DEB_SHA512="$(jq -r '[.File[] | select(.Url | endswith(".deb"))][0].Sha512CheckSum' <<<"$REL")"
REL_DATE="$(jq -r '.ReleaseDate[0:10]' <<<"$REL")"
[[ "$DEB_URL" == https://proton.me/* ]] || { echo "Unexpected download URL: $DEB_URL" >&2; exit 1; }

echo "==> Proton Pass $VERSION ($REL_DATE)"

# --- appimagetool ----------------------------------------------------------
TOOL="$WORK/appimagetool"
dl "$TOOL" "$APPIMAGETOOL_URL"
echo "$APPIMAGETOOL_SHA256  $TOOL" | sha256sum -c --quiet
chmod +x "$TOOL"
echo "    appimagetool $APPIMAGETOOL_VERSION sha256 OK"

# --- Runtime: download + verify signature ----------------------------------
RUNTIME="$WORK/runtime-x86_64"
dl "$RUNTIME" "$RUNTIME_URL"
dl "$RUNTIME.sig" "$RUNTIME_URL.sig"
export GNUPGHOME="$WORK/gnupg"; mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --import "$RUNTIME_KEY"
STATUS="$(gpg --batch --status-fd 1 --verify "$RUNTIME.sig" "$RUNTIME" 2>/dev/null || true)"
grep -q "^\[GNUPG:\] VALIDSIG $RUNTIME_KEY_FPR " <<<"$STATUS" \
  || { echo "Runtime signature verification FAILED" >&2; exit 1; }
RUNTIME_SHA256="$(sha256sum "$RUNTIME" | cut -d' ' -f1)"
echo "    runtime signature OK (key $RUNTIME_KEY_FPR)"

# --- Proton Pass .deb ------------------------------------------------------
dl "$WORK/proton-pass.deb" "$DEB_URL"
echo "$DEB_SHA512  $WORK/proton-pass.deb" | sha512sum -c --quiet
echo "    deb sha512 OK"

# --- AppDir ----------------------------------------------------------------
dpkg-deb -x "$WORK/proton-pass.deb" "$WORK/deb"
APPDIR="$WORK/ProtonPass.AppDir"
mkdir -p "$APPDIR/usr/share/metainfo"
cp -a "$WORK/deb/usr/lib" "$APPDIR/usr/"
cp -a "$WORK/deb/usr/share/." "$APPDIR/usr/share/"
install -m 755 "$ROOT/appdir/AppRun" "$APPDIR/AppRun"
cp "$WORK/deb/usr/share/applications/proton-pass.desktop" "$APPDIR/$APP_ID.desktop"
cp "$WORK/deb/usr/share/applications/proton-pass.desktop" "$APPDIR/usr/share/applications/$APP_ID.desktop"
# Upstream ships an SVG under a .png name
cp "$WORK/deb/usr/share/pixmaps/proton-pass.png" "$APPDIR/proton-pass.svg"
sed -e "s/@VERSION@/$VERSION/" -e "s/@DATE@/$REL_DATE/" \
  "$ROOT/appdir/$APP_ID.appdata.xml" > "$APPDIR/usr/share/metainfo/$APP_ID.appdata.xml"

if command -v desktop-file-validate >/dev/null; then
  desktop-file-validate "$APPDIR/$APP_ID.desktop"
fi

# --- Build -----------------------------------------------------------------
mkdir -p "$ROOT/dist"
NAME="Proton_Pass-$VERSION-x86_64.AppImage"
rm -f "$ROOT/dist/$NAME" "$ROOT/dist/$NAME.zsync"
(
  cd "$ROOT/dist"
  ARCH=x86_64 VERSION="$VERSION" APPIMAGE_EXTRACT_AND_RUN=1 \
    "$TOOL" --runtime-file "$RUNTIME" -u "$UPDATE_INFO" "$APPDIR" "$NAME"
  sha256sum "$NAME" > "$NAME.sha256"
)

cat > "$ROOT/dist/build-info.txt" <<EOF
version=$VERSION
deb_url=$DEB_URL
deb_sha512=$DEB_SHA512
runtime_sha256=$RUNTIME_SHA256
appimagetool_version=$APPIMAGETOOL_VERSION
update_info=$UPDATE_INFO
EOF

echo "==> Built dist/$NAME"
cat "$ROOT/dist/$NAME.sha256"

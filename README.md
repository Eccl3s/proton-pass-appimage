# Proton Pass AppImage

Unofficial AppImage builds of [Proton Pass](https://proton.me/pass) for x86_64 Linux,
repackaged unmodified from Proton's official `.deb`. Not affiliated with Proton AG.

A GitHub Actions workflow checks Proton's release feed every 6 hours and publishes a
new [release](../../releases) when a new stable version appears.

## Run

```bash
chmod +x Proton_Pass-*-x86_64.AppImage
./Proton_Pass-*-x86_64.AppImage
```

Needs a `fusermount` binary (the `fuse3` package). libfuse2 is **not** required: the
AppImage runtime links FUSE 3 statically. Without FUSE, use `--appimage-extract-and-run`.

### Updates

Each AppImage embeds update information
(`gh-releases-zsync|Eccl3s|proton-pass-appimage|latest|Proton_Pass-*-x86_64.AppImage.zsync`)
and every release ships a `.zsync` file, so tools such as AppImageUpdate or Gear Lever
can do delta updates. This only works while the repository is **public**; GitHub does
not serve private release assets anonymously.

### Sandbox

AppImages can't ship a setuid `chrome-sandbox`. The launcher (`appdir/AppRun`) uses
Chromium's user-namespace sandbox when the kernel permits it, and otherwise falls back
to `--no-sandbox` with a warning on stderr. Ubuntu 23.10+ restricts unprivileged user
namespaces via AppArmor; to keep the sandbox there, add an AppArmor profile for the
AppImage or set `kernel.apparmor_restrict_unprivileged_userns=0`.

## How it's built

`build.sh`:

1. Reads `https://proton.me/download/PassDesktop/linux/x64/version.json` and picks the
   latest stable version (or the one given as an argument).
2. Downloads the `.deb` from proton.me and verifies its SHA-512 against the feed.
3. Downloads [appimagetool](https://github.com/AppImage/appimagetool) **1.9.1** (tagged
   release) and verifies it against a pinned SHA-256. Upstream publishes no signature.
4. Downloads the latest [type2 runtime](https://github.com/AppImage/type2-runtime) and
   its `.sig`, and verifies the GPG signature against the AppImage project's key in
   `keys/type2-runtime.asc` (fingerprint `570C 77AC EA40 C0F1 B758 902C BF96 CCA5 6490 F695`).
   The build fails if the signature doesn't verify.
5. Assembles an AppDir: Proton's `usr/lib` and `usr/share` copied unmodified, plus
   `AppRun`, a root desktop file, the icon and AppStream metadata
   (`appdir/io.github.eccl3s.ProtonPass.appdata.xml`).
6. Runs appimagetool with `--runtime-file` (the verified runtime) and `-u` (update
   info), producing the AppImage, `.zsync` and `.sha256`.

Pull requests run the build without publishing and attach the result as a workflow artifact.

Build locally (Debian/Ubuntu):

```bash
sudo apt install curl jq gpg zsync appstream desktop-file-utils
./build.sh            # latest
./build.sh 1.44.1     # specific version
```

## Verify a release

Release notes list the upstream .deb SHA-512, the runtime SHA-256 and the AppImage SHA-256.
To check the contents without running the AppImage:

```bash
# Find where the squashfs starts (= size of the runtime ELF)
OFFSET=$(python3 -c "import sys;d=open(sys.argv[1],'rb').read(64);import struct;sh_off=struct.unpack_from('<Q',d,0x28)[0];sh_sz,sh_n=struct.unpack_from('<HH',d,0x3A);print(sh_off+sh_sz*sh_n)" Proton_Pass-X-x86_64.AppImage)

# 1. Runtime is the signed upstream one
head -c "$OFFSET" Proton_Pass-X-x86_64.AppImage > runtime
#    (compare its sha256 with the release notes; note the embedded update info
#     changes the bytes vs. the raw upstream download)

# 2. Payload matches Proton's .deb
dpkg-deb -x proton-pass_X_amd64.deb deb
unsquashfs -o "$OFFSET" -d appimg Proton_Pass-X-x86_64.AppImage
diff -r deb/usr/lib appimg/usr/lib
diff -r deb/usr/share appimg/usr/share   # only difference: added metainfo/

# 3. Read the added files
cat appimg/AppRun appimg/*.desktop appimg/usr/share/metainfo/*.xml
```

## Updating pinned inputs

- **appimagetool:** change `APPIMAGETOOL_VERSION` and `APPIMAGETOOL_SHA256` in `build.sh`.
- **Runtime signing key:** if the AppImage project rotates its key, replace
  `keys/type2-runtime.asc` and `RUNTIME_KEY_FPR` (check the new fingerprint upstream).

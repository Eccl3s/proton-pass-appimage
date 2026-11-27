# Proton Pass AppImage

Unofficial AppImage builds of [Proton Pass](https://proton.me/pass) for x86_64 Linux,
repackaged from Proton's official `.deb`. Not affiliated with Proton AG.

A GitHub Actions workflow checks Proton's release feed every 6 hours and publishes a
new [release](../../releases) when a new stable version appears.

## Run

```bash
chmod +x Proton_Pass-*-x86_64.AppImage
./Proton_Pass-*-x86_64.AppImage
```

Needs a `fusermount` binary (the `fuse3` package). libfuse2 is **not** required — the
AppImage runtime has FUSE 3 statically linked. Without FUSE, use `--appimage-extract-and-run`.

### Sandbox

AppImages can't ship a setuid `chrome-sandbox`. The launcher (`appdir/AppRun`) uses
Chromium's user-namespace sandbox when the kernel permits it, and otherwise falls back
to `--no-sandbox` with a warning on stderr. Ubuntu 23.10+ restricts unprivileged user
namespaces via AppArmor; to keep the sandbox there, add an AppArmor profile for the
AppImage or set `kernel.apparmor_restrict_unprivileged_userns=0`.

## How it's built

`build.sh`:

1. Reads `https://proton.me/download/PassDesktop/linux/x64/version.json`, picks the
   latest stable version (or the one given as an argument).
2. Downloads the `.deb` from proton.me and verifies its SHA-512 against the feed.
3. Copies `usr/lib` and `usr/share` unmodified into an AppDir, adds `AppRun`, the
   desktop file and icon.
4. Packs it with `mksquashfs` (zstd) and prepends the AppImage
   [type2 runtime](https://github.com/AppImage/type2-runtime) vendored in `runtime/`
   (SHA-256 pinned in `build.sh`).

Build locally (Debian/Ubuntu: `sudo apt install squashfs-tools jq curl`):

```bash
./build.sh            # latest
./build.sh 1.44.1     # specific version
```

## Verify a release

Without running the AppImage (offset = size of the runtime, 944632 bytes):

```bash
# 1. Runtime is the pinned upstream one
head -c 944632 Proton_Pass-X-x86_64.AppImage | sha256sum   # == runtime/runtime-x86_64

# 2. Payload is identical to Proton's .deb
dpkg-deb -x proton-pass_X_amd64.deb deb
unsquashfs -o 944632 -d appimg Proton_Pass-X-x86_64.AppImage
diff -r deb/usr/lib appimg/usr/lib && diff -r deb/usr/share appimg/usr/share && echo IDENTICAL

# 3. Read the only added code
cat appimg/AppRun
```

## Updating the runtime

Download a new `runtime-x86_64` from the type2-runtime releases, replace
`runtime/runtime-x86_64`, update `RUNTIME_SHA256` in `build.sh` and the offset in this README.

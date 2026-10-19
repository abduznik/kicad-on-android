# KiCad on Android

Run the full desktop **KiCad** on an Android phone or tablet. A one-shot installer sets up
Termux + Termux:X11 + a Debian guest with KiCad, and a small launcher APK gives you a real app icon,
one-tap install, launch and stop.

> Status: the installer is verified on a real device (KiCad starts and runs). The launcher APK's
> hand-off to Termux is still being verified; see [Troubleshooting](docs/TROUBLESHOOTING.md).
> This is the real desktop UI, not a touch-first redesign yet (see [Roadmap](docs/ROADMAP.md)).

## What you get
- Full KiCad (schematic, PCB, symbol/footprint editors, `kicad-cli`, Python scripting, plugins)
- Projects, scripts and plugins in **Internal storage/KiCad**, visible to any Android app
- `kicad-start`, `kicad-stop`, `kicad-shell`, `kicad-cli`, `kicad-pip`, `kicad-plugin`
- A launcher APK with a status screen, one-tap install/launch/stop, and a pinned home-screen shortcut

## Requirements
- Android 8+, arm64 recommended, about 6 GB free (10 GB with 3D models)
- [Termux](https://github.com/termux/termux-app/releases) (F-Droid or GitHub build, not the Play Store build)
- [Termux:X11](https://github.com/termux/termux-x11/releases) app
- Optional: Termux:Widget

## Quick start (APK)
1. Install Termux and Termux:X11.
2. Install `KiCadLauncher.apk` from the [latest release](../../releases/latest) (allow installs from unknown sources).
3. Open **KiCad Launcher** and follow the three steps:
   1. Paste the shown command in Termux (enables `allow-external-apps`), then tap **Grant permission**.
   2. **Install in Termux** (10-20 minutes the first time; options for 3D models, high-DPI, experimental GPU).
   3. **Launch KiCad**. Use "Add icon to home screen" for a direct launch icon.

## Quick start (script only)
In Termux:
```bash
pkg install -y curl
curl -fsSL https://github.com/abduznik/kicad-on-android/releases/latest/download/install.sh -o install.sh
bash install.sh
kicad-start
```
(If the repository is private, copy `install.sh` onto the device instead.)

Options (environment variables):

| Variable | Default | Meaning |
|---|---|---|
| `KICAD_DISTRO` | `debian` | guest distro, `debian` or `ubuntu` |
| `KICAD_3D` | `0` | `1` also installs the 3D model library (+3 GB) |
| `KICAD_GPU` | `software` | `virgl` = experimental GPU path |
| `KICAD_SCALE` | `1` | GTK UI scale for high-DPI screens (try `2`) |
| `KICAD_DPI` | empty | X server DPI |
| `KICAD_FORCE` | `0` | `1` skips the free-space check |

`bash install.sh --update` upgrades KiCad, `--uninstall` removes everything but your KiCad folder.

## Touch tips
In Termux:X11 preferences set Touch mode to **Simulated touchscreen** (tap = click, long-tap = hold/drag,
two-finger tap = right-click, two-finger swipe = scroll). A three-finger swipe down shows the
Esc/Ctrl/Alt/arrow key bar, which KiCad needs. Enable Fullscreen there too.

## Plugins and scripts
See [docs/PLUGINS.md](docs/PLUGINS.md): KiCad's Plugin and Content Manager, legacy plugins in
`KiCad/scripts/plugins`, IPC plugins in `KiCad/scripts/ipc-plugins`, `kicad-plugin`, `kicad-pip`.

## Build it yourself
### The APK
Needs the Android SDK (platform `android-34`, build-tools `34.0.0`), a JDK 17+ and `zip`. No Gradle.
```bash
export ANDROID_HOME=$HOME/Android/Sdk      # your SDK location
./apk/build.sh                             # -> apk/build/KiCadLauncher.apk
```
`build.sh` bundles the current `install.sh` into the app, signs with `apk/debug.keystore`
(created on first run), and prints the signature.
Variables: `BUILD_TOOLS`, `JAVA_HOME`, `KEYSTORE`, `VERSION_CODE`, `VERSION_NAME`.

Releases are built and signed by GitHub Actions (`.github/workflows/release.yml`) from the repository
secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD` and `KEY_ALIAS`; pushing a `v*` tag publishes a
release. To use your own key in a fork, create a keystore with `keytool`, base64 it
(`base64 -w0 my.keystore`) and set those four secrets with `gh secret set`.

Signing note: Android only updates an installed app when the new APK has the same signing key.
Release APKs are signed with the maintainer's key; an APK you build is signed with yours, so uninstall
the released one first (or keep one key for all your builds).

### Re-creating the whole thing from scratch
1. `install.sh` is the single source of truth for the device setup; read it top to bottom, it is one file.
2. `apk/` is a plain Android project: `AndroidManifest.xml`, `res/`, `java/com/yan/kicadbox/MainActivity.java`.
   `build.sh` runs `aapt2 compile/link`, `javac`, `d8`, `zipalign`, `apksigner`.
3. `test/sim.sh` simulates Termux with stub commands and asserts on everything the installer generates:
   ```bash
   bash test/sim.sh
   ```
4. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the pieces fit.

## Layout
```
install.sh              the one-shot device installer (also bundled in the APK)
apk/                    launcher app sources + build.sh
test/sim.sh             stubbed-Termux simulation of install + launch
docs/                   architecture, troubleshooting, plugins, roadmap
.github/workflows/      CI: simulation + APK build
```

## Limitations
- Desktop UI on a touchscreen; GPU acceleration is device dependent, software GL is the default.
- Debian provides the KiCad version (typically one release behind upstream).
- Requires Termux and Termux:X11; Android does not let one app silently control another, so step 1 is manual.

## License
MIT for the scripts and app in this repository. KiCad itself is GPL-3.0 and is installed from Debian packages,
not redistributed here.

# Architecture

```
Android
├─ KiCad Launcher (this APK)              status UI, install/launch/stop, pinned shortcut
│    └─ sends com.termux.RUN_COMMAND ───▶ Termux (RunCommandService)
├─ Termux                                   runs install.sh, kicad-start, kicad-stop ...
│    ├─ termux-x11 :0   (X server) ◀──────▶ Termux:X11 app (draws the screen, touch/keyboard)
│    └─ proot-distro Debian guest
│         └─ openbox + KiCad  (DISPLAY=:0 over the shared /tmp socket)
└─ Internal storage/KiCad  ◀── bind-mounted as ~/KiCad in the guest
     ├─ projects/            default KiCad Documents folder
     ├─ scripts/plugins/     legacy (SWIG) action plugins
     ├─ scripts/ipc-plugins/ KiCad 9+ IPC (kipy) plugins
     └─ libraries/
```

## Why this shape
- A native port needs wxWidgets on Android (wxQt), which is not mature, and a rewritten touch UI.
  Running the real desktop build in a guest gives the full app, Python scripting and plugins today.
- Termux:X11 is a native Android X server: no VNC, no network hop, hardware keyboard/mouse support.
- Projects and scripts live in shared storage so any Android app (file manager, Syncthing, Drive) can reach them.
  Python venvs and the Plugin and Content Manager data stay inside the guest, because shared storage
  cannot hold symlinks or executables.

## Launch sequence (`kicad-start`)
1. Hold a wake lock, kill stale X servers.
2. `termux-x11 :0` and wait for the socket in `$PREFIX/tmp/.X11-unix`.
3. Open the Termux:X11 activity.
4. `proot-distro login` the guest with `--shared-tmp`, bind the storage folders, set `DISPLAY=:0`,
   software GL by default, then `dbus-launch openbox-session & kicad`.
5. When KiCad exits: stop X, release the wake lock. GTK chatter goes to `~/.cache/kicad-termux/last.log`.

## The APK
Plain Android framework code (no AndroidX, no Gradle). It bundles `install.sh` as an asset and
passes it to Termux as `bash -c <script>` via `RUN_COMMAND`. Termux must have
`allow-external-apps=true` and the app must hold the `com.termux.permission.RUN_COMMAND` runtime permission.
Scripts are executed as `bash <absolute path>` because the run-command environment has no `/usr/bin/env`.

## Testing
`test/sim.sh` runs the whole installer and launcher against stub `pkg`, `proot-distro`, `termux-x11`,
`am` and `apt-get` in a temporary fake Termux, then asserts on the generated files and calls.
It cannot prove that real Debian packages install or that the GL path works; that needs a device.

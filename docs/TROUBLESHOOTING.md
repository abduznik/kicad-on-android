# Troubleshooting

**Termux:X11 says "not connected".** Nothing started the X server. Run `kicad-start` in Termux directly;
if that works, the problem is the APK handoff. Tick "Show Termux while launching" in the app and read the error.

**`bad interpreter: /usr/bin/env`.** An older install wrote `#!/usr/bin/env bash` into the commands.
Run `termux-fix-shebang $PREFIX/bin/kicad-*` or re-run `install.sh`.

**App says permission denied.** In Termux: `allow-external-apps=true` in `~/.termux/termux.properties`,
then `termux-reload-settings` (or restart Termux), then tap Grant permission in the app.

**Sessions killed in the background (Android 12+).** Disable the phantom process killer:
Android 14+: Developer options, "Disable child process restrictions".
Android 12/13: `adb shell settings put global settings_enable_monitor_phantom_procs false`.

**Blank or slow canvas.** KiCad Preferences, Graphics, choose "Fallback" (Cairo). Optionally try
`KICAD_GPU=virgl` (experimental; works on Adreno, reported broken on Mali).

**GTK `pixman_region32_init_rect: Invalid rectangle` messages.** Cosmetic GTK3 layout noise; they are
written to `~/.cache/kicad-termux/last.log`. Use `kicad-start --verbose` to see them.

**No storage folder.** Run `termux-setup-storage`, allow it, re-run the installer.

**Not enough space.** About 6 GB (10 GB with 3D models). `KICAD_FORCE=1` skips the check.

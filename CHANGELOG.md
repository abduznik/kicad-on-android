# Changelog

## 0.4 - launcher APK, shebang-proof launch (first public release)
- APK runs `exec bash <prefix>/bin/kicad-start`, never relying on the script's first line.
- Installer writes an absolute `#!$PREFIX/bin/bash` shebang into every command it installs.

## 0.3
- APK launches through a login bash (`bash -lc`).

## 0.2
- "Show Termux while launching" option for debugging; clearer permission errors.

## 0.1
- First launcher APK: status screen, one-tap install, launch/stop, pinned home-screen shortcut.
- Installer: Termux:X11 + proot-distro Debian + KiCad, shared-storage project/script folders,
  plugin helpers (`kicad-plugin`, `kicad-pip`), `kicad-cli` passthrough.

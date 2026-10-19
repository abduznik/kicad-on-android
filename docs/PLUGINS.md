# Plugins and scripts

- **Plugin and Content Manager**: Tools, Plugin and Content Manager inside KiCad. The guest has internet,
  installs land inside the guest.
- **Legacy (SWIG) action plugins**: drop a folder in `Internal storage/KiCad/scripts/plugins`.
  It is linked into KiCad's user scripting folder.
- **KiCad 9+ IPC plugins**: drop them in `KiCad/scripts/ipc-plugins`. In KiCad, enable the API
  (Preferences, Plugins) and set the interpreter to `/usr/bin/python3`. KiCad builds each plugin's venv in the guest.
- **Helpers**
  ```
  kicad-plugin add <git-url|zip> [name] [--ipc]
  kicad-plugin list
  kicad-plugin remove <name> [--ipc]
  kicad-pip <python-package>
  kicad-cli ...        headless exports, DRC/ERC, gerbers
  kicad-shell          shell inside the guest
  ```

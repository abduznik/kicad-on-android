#!/usr/bin/env bash
# KiCad on Android — one-shot Termux installer.
#
# Needs: Termux (F-Droid/GitHub build) + the Termux:X11 app. Optional: Termux:Widget for a home-screen button.
# Usage:  bash install.sh [--update | --uninstall | --help]
# Env:    KICAD_DISTRO=debian|ubuntu   guest distro (default debian)
#         KICAD_3D=1                   also install the 3D model library (+~3 GB)
#         KICAD_GPU=software|virgl     OpenGL path (default software; virgl is experimental)
#         KICAD_SCALE=1                GTK UI scale for high-DPI screens (try 2)
#         KICAD_DPI=160                X server DPI (empty = Termux:X11 default)
#         KICAD_FORCE=1                skip the free-space check
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BIN="$PREFIX/bin"
CONF_DIR="$HOME/.config/kicad-termux"
SHORTCUTS="$HOME/.shortcuts"
DISTRO="${KICAD_DISTRO:-debian}"
WITH_3D="${KICAD_3D:-0}"
GPU="${KICAD_GPU:-software}"
SCALE="${KICAD_SCALE:-1}"
DPI="${KICAD_DPI:-}"
ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"
SHARED="$HOME/storage/shared"

c() { printf '\033[%sm' "$1"; }
step() { printf '\n%s==>%s %s\n' "$(c 1\;36)" "$(c 0)" "$*"; }
ok()   { printf '%s ok%s %s\n' "$(c 32)" "$(c 0)" "$*"; }
warn() { printf '%swarn%s %s\n' "$(c 33)" "$(c 0)" "$*" >&2; }
die()  { printf '%sFAIL%s %s\n' "$(c 31)" "$(c 0)" "$*" >&2; exit 1; }

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

preflight() {
  step "Checking environment"
  [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ] || die "Run this inside Termux."
  case "$(uname -m)" in
    aarch64|x86_64) ;;
    *) warn "Unsupported/untested CPU $(uname -m); KiCad will be very slow or unavailable." ;;
  esac
  case "$DISTRO" in debian|ubuntu) ;; *) die "KICAD_DISTRO must be debian or ubuntu" ;; esac
  case "$GPU" in software|virgl) ;; *) die "KICAD_GPU must be software or virgl" ;; esac

  local need_gb=6 avail_kb
  [ "$WITH_3D" = 1 ] && need_gb=10
  avail_kb="$(df -Pk "$HOME" | awk 'NR==2{print $4}')"
  if [ "$((avail_kb / 1024 / 1024))" -lt "$need_gb" ] && [ "${KICAD_FORCE:-0}" != 1 ]; then
    die "Need ~${need_gb} GB free in Termux storage, have $((avail_kb / 1024 / 1024)) GB. (KICAD_FORCE=1 to ignore)"
  fi
  if command -v pm >/dev/null 2>&1 && ! pm list packages 2>/dev/null | grep -q 'com.termux.x11'; then
    warn "Termux:X11 app not detected. Install it (github.com/termux/termux-x11 releases) before launching."
  fi
  if command -v pm >/dev/null 2>&1 && ! pm list packages 2>/dev/null | grep -q 'com.termux.widget'; then
    warn "Termux:Widget not detected - needed only for the home-screen button (F-Droid / GitHub)."
  fi
  ok "environment looks fine"
}

install_termux_packages() {
  step "Installing Termux packages (X11, proot-distro)"
  export DEBIAN_FRONTEND=noninteractive
  pkg update -y
  # Termux does not support partial upgrades: stale libraries/interpreters (e.g. python for proot-distro) break tools.
  pkg upgrade -y -o Dpkg::Options::=--force-confold
  pkg install -y x11-repo
  pkg update -y
  local pkgs=(termux-x11-nightly proot-distro)
  [ "$GPU" = virgl ] && pkgs+=(virglrenderer-android)
  pkg install -y "${pkgs[@]}"
  # proot-distro is a Python script; repair it if its interpreter is missing or mismatched.
  if ! proot-distro list >/dev/null 2>&1; then
    warn "proot-distro does not run; reinstalling python and proot-distro"
    pkg reinstall -y python proot-distro
    proot-distro list >/dev/null 2>&1 || die "proot-distro is still broken. Run: pkg upgrade -y && pkg reinstall -y python proot-distro"
  fi
  ok "termux packages installed"
}

setup_storage() {
  step "Setting up shared storage"
  if [ ! -d "$SHARED" ]; then
    echo "Android will ask for storage permission - tap Allow."
    termux-setup-storage || true
    for _ in $(seq 1 60); do [ -d "$SHARED" ] && break; sleep 1; done
  fi
  [ -d "$SHARED" ] || die "No storage access. Run termux-setup-storage, allow it, then re-run this script."
  mkdir -p "$SHARED/KiCad/projects" "$SHARED/KiCad/scripts/plugins" "$SHARED/KiCad/scripts/ipc-plugins" "$SHARED/KiCad/libraries"
  ok "projects/scripts folder: Internal storage/KiCad  (projects, scripts, libraries)"
}

install_distro() {
  step "Installing $DISTRO rootfs (proot-distro)"
  if [ -d "$ROOTFS" ]; then ok "$DISTRO already installed"; else proot-distro install "$DISTRO"; fi
}

write_config() {
  step "Writing config"
  mkdir -p "$CONF_DIR"
  cat > "$CONF_DIR/env" <<EOF
KICAD_DISTRO=$DISTRO
KICAD_GPU=$GPU
KICAD_SCALE=$SCALE
KICAD_DPI=$DPI
EOF
  ok "$CONF_DIR/env  (edit to change GPU mode / UI scale)"
}

guest_setup() {
  step "Installing KiCad inside $DISTRO (this is the long part)"
  local script="$PREFIX/tmp/kicad-guest-setup.sh"
  mkdir -p "$PREFIX/tmp"
  cat > "$script" <<'GUEST'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates openbox dbus-x11 x11-xserver-utils xauth fonts-dejavu-core \
  libgl1-mesa-dri python3 python3-pip python3-venv git unzip curl \
  kicad kicad-symbols kicad-footprints kicad-templates
[ "${WITH_3D:-0}" = 1 ] && apt-get install -y --no-install-recommends kicad-packages3d
apt-get clean

# Openbox: maximise normal windows (no mouse-resize on a touchscreen); dialogs stay floating.
mkdir -p "$HOME/.config/openbox"
RC="${OPENBOX_RC:-/etc/xdg/openbox/rc.xml}"
if [ -f "$RC" ]; then
  cp "$RC" "$HOME/.config/openbox/rc.xml"
  if grep -q '<applications>' "$HOME/.config/openbox/rc.xml"; then
    sed -i 's#<applications>#<applications>\n    <application type="normal"><maximized>yes</maximized><decor>no</decor></application>#' "$HOME/.config/openbox/rc.xml"
  fi
fi

# Storage layout: Android "KiCad" folder is visible as ~/KiCad and as KiCad's default Documents folder.
mkdir -p "$HOME/KiCad/scripts/plugins" "$HOME/KiCad/scripts/ipc-plugins" "$HOME/Documents"
ln -sfn "$HOME/KiCad/projects" "$HOME/Documents/KiCad"

# Action plugins / Python scripts dropped in KiCad/scripts/plugins are picked up automatically.
ver="$(dpkg-query -W -f='${Version}' kicad 2>/dev/null | sed -E 's/^([0-9]+:)?([0-9]+)\.([0-9]+).*/\2.\3/')"
if [ -n "$ver" ]; then
  d="$HOME/.local/share/kicad/$ver/scripting"
  mkdir -p "$d"
  rmdir "$d/plugins" 2>/dev/null || true
  ln -sfn "$HOME/KiCad/scripts/plugins" "$d/plugins"
  # KiCad 9+ IPC (kipy) plugins; their venvs are created by KiCad in ~/.cache inside the guest.
  u="$HOME/.local/share/kicad/$ver"
  rmdir "$u/plugins" 2>/dev/null || true
  ln -sfn "$HOME/KiCad/scripts/ipc-plugins" "$u/plugins"
fi
echo "KICAD_VERSION=${ver:-unknown}"
GUEST
  chmod +x "$script"
  proot-distro login "$DISTRO" --shared-tmp --bind "$SHARED/KiCad:/root/KiCad" -- \
    env WITH_3D="$WITH_3D" bash /tmp/kicad-guest-setup.sh
  rm -f "$script"
  ok "KiCad installed in the guest"
}

install_launchers() {
  step "Installing launch commands"
  mkdir -p "$BIN"

  cat > "$BIN/kicad-start" <<'LAUNCH'
#!/usr/bin/env bash
# Start Termux:X11, then KiCad inside the proot guest. Args are passed to kicad (guest paths, e.g. /root/KiCad/projects/x/x.kicad_pro).
. "$HOME/.config/kicad-termux/env"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
SHARED="$HOME/storage/shared"
VERBOSE=0; [ "${1:-}" = --verbose ] && { VERBOSE=1; shift; }
KLOG="$HOME/.cache/kicad-termux/last.log"; mkdir -p "$(dirname "$KLOG")"
termux-wake-lock 2>/dev/null || true

pkill -f 'termux-x11 ' 2>/dev/null || true
pkill -f virgl_test_server 2>/dev/null || true
rm -f "$PREFIX"/tmp/.X11-unix/X0 "$PREFIX"/tmp/.X0-lock 2>/dev/null || true
termux-x11 :0 ${KICAD_DPI:+-dpi "$KICAD_DPI"} >/dev/null 2>&1 &
for _ in $(seq 1 30); do [ -S "$PREFIX/tmp/.X11-unix/X0" ] && break; sleep 0.5; done
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || \
  echo "Could not open the Termux:X11 app - open it manually." >&2

GL_ENV=(LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe)
if [ "${KICAD_GPU:-software}" = virgl ]; then
  virgl_test_server_android >/dev/null 2>&1 &
  GL_ENV=(GALLIUM_DRIVER=virpipe MESA_GL_VERSION_OVERRIDE=4.0)
fi

run_guest() {
  proot-distro login "$KICAD_DISTRO" --shared-tmp \
    --bind "$SHARED/KiCad:/root/KiCad" --bind "$SHARED:/root/sdcard" -- \
    env DISPLAY=:0 GDK_SCALE="${KICAD_SCALE:-1}" NO_AT_BRIDGE=1 GTK_A11Y=none "${GL_ENV[@]}" \
    dbus-launch --exit-with-session bash -c \
    'openbox-session >/dev/null 2>&1 & sleep 1; exec kicad "$@"' _ "$@"
}
# GTK/pixman/AT-SPI chatter goes to a log instead of the terminal (--verbose shows it).
if [ "$VERBOSE" = 1 ]; then run_guest "$@"; else run_guest "$@" >"$KLOG" 2>&1; fi
rc=$?

pkill -f 'termux-x11 ' 2>/dev/null || true
pkill -f virgl_test_server 2>/dev/null || true
termux-wake-unlock 2>/dev/null || true
exit $rc
LAUNCH

  cat > "$BIN/kicad-stop" <<'STOP'
#!/usr/bin/env bash
pkill -f 'termux-x11 ' 2>/dev/null || true
pkill -f virgl_test_server 2>/dev/null || true
pkill -f 'proot.*kicad' 2>/dev/null || true
termux-wake-unlock 2>/dev/null || true
echo "KiCad stopped."
STOP

  cat > "$BIN/kicad-shell" <<'SHELL'
#!/usr/bin/env bash
# Shell inside the KiCad guest (apt, python, pip...). Your Android folders: ~/KiCad and ~/sdcard.
. "$HOME/.config/kicad-termux/env"
SHARED="$HOME/storage/shared"
exec proot-distro login "$KICAD_DISTRO" --shared-tmp \
  --bind "$SHARED/KiCad:/root/KiCad" --bind "$SHARED:/root/sdcard" -- "${@:-bash}"
SHELL

  cat > "$BIN/kicad-cli" <<'CLI'
#!/usr/bin/env bash
# Headless kicad-cli (exports, DRC/ERC, gerbers) for use from Termux scripts.
exec kicad-shell kicad-cli "$@"
CLI

  cat > "$BIN/kicad-pip" <<'PIP'
#!/usr/bin/env bash
# pip for KiCad's (system) Python in the guest - use for libraries that legacy plugins import.
exec kicad-shell pip install --break-system-packages "$@"
PIP

  cat > "$BIN/kicad-plugin" <<'PLUGIN'
#!/usr/bin/env bash
# kicad-plugin add <git-url|zip-path-or-url> [name] [--ipc]   install a plugin into Internal storage/KiCad/scripts/{plugins|ipc-plugins}
# kicad-plugin list | remove <name> [--ipc]
# Prefer KiCad's own Plugin and Content Manager (Tools -> Plugin and Content Manager) for catalogue plugins.
set -euo pipefail
cmd="${1:-list}"; shift || true
sub=plugins; args=()
for a in "$@"; do [ "$a" = --ipc ] && sub=ipc-plugins || args+=("$a"); done
dir="/root/KiCad/scripts/$sub"
case "$cmd" in
  list)   kicad-shell bash -c "ls -1 /root/KiCad/scripts/plugins /root/KiCad/scripts/ipc-plugins" ;;
  remove) kicad-shell rm -rf "$dir/${args[0]:?usage: kicad-plugin remove <name> [--ipc]}" ;;
  add)
    src="${args[0]:?usage: kicad-plugin add <git-url|zip> [name] [--ipc]}"
    # A local zip lives on the Termux side; hand it to the guest through the shared /tmp.
    if [ -f "$src" ]; then cp "$src" "${PREFIX:-/data/data/com.termux/files/usr}/tmp/kp-$$.zip"; name_src="$src"; src="/tmp/kp-$$.zip"; fi
    name="${args[1]:-$(basename "${name_src:-${src%.git}}" .zip)}"
    case "$src" in
      *.zip) kicad-shell bash -c "set -e; t=\$(mktemp -d); { [ -f '$src' ] && cp '$src' \$t/p.zip || curl -fsSL -o \$t/p.zip '$src'; }; mkdir -p '$dir/$name'; unzip -oq \$t/p.zip -d '$dir/$name'" ;;
      *)     kicad-shell bash -c "set -e; rm -rf '$dir/$name'; git clone --depth 1 '$src' '$dir/$name'; rm -rf '$dir/$name/.git'" ;;
    esac
    echo "Installed $name -> Internal storage/KiCad/scripts/$sub/$name. Restart KiCad (or Tools -> External Plugins -> Refresh)." ;;
  *) sed -n '2,4p' "$0"; exit 1 ;;
esac
PLUGIN

  chmod +x "$BIN/kicad-start" "$BIN/kicad-stop" "$BIN/kicad-shell" "$BIN/kicad-cli" "$BIN/kicad-pip" "$BIN/kicad-plugin"

  # Absolute shebang: Termux's RUN_COMMAND (used by the Android launcher app) has no /usr/bin/env.
  for f in kicad-start kicad-stop kicad-shell kicad-cli kicad-pip kicad-plugin; do
    sed -i "1s|.*|#!$PREFIX/bin/bash|" "$BIN/$f"
  done

  mkdir -p "$SHORTCUTS"
  printf '#!/usr/bin/env bash\nexec kicad-start\n' > "$SHORTCUTS/KiCad"
  printf '#!/usr/bin/env bash\nexec kicad-stop\n'  > "$SHORTCUTS/KiCad-Stop"
  chmod +x "$SHORTCUTS/KiCad" "$SHORTCUTS/KiCad-Stop"
  ok "kicad-start/stop/shell/cli/pip/plugin + Termux:Widget shortcuts"
}

verify() {
  step "Verifying"
  local v
  v="$(proot-distro login "$DISTRO" --shared-tmp -- kicad-cli version 2>/dev/null | tail -n1 || true)"
  [ -n "$v" ] && ok "KiCad $v" || warn "kicad-cli did not answer; run kicad-shell and check by hand."
}

finish() {
  cat <<EOF

$(c 1\;32)Done.$(c 0)
  Launch      : kicad-start  (--verbose shows GTK logs; otherwise ~/.cache/kicad-termux/last.log)
  Projects    : Internal storage/KiCad/projects   (~/KiCad/projects in kicad-shell)
  Plugins     : Tools -> Plugin and Content Manager (online catalogue, installs inside the guest), or
                kicad-plugin add <git-url|zip> [--ipc]  /  drop folders in KiCad/scripts/plugins (legacy)
                or KiCad/scripts/ipc-plugins (KiCad 9+ IPC plugins; also enable Preferences -> Plugins -> KiCad API
                and point it to /usr/bin/python3)
  Python deps : kicad-pip <package>        Headless: kicad-cli ...        Guest shell: kicad-shell
  Tune        : $CONF_DIR/env  (KICAD_GPU, KICAD_SCALE, KICAD_DPI)

Home-screen button: install Termux:Widget, long-press home -> Widgets -> Termux:Widget (resize it
to show the list), tap "KiCad". Some launchers also let you drag one entry out as its own icon.

Termux:X11 touch tips: open its Preferences -> set Touch mode to "Simulated touchscreen" (tap=click,
long-tap=hold/drag, two-finger tap=right-click, two-finger swipe=scroll); three-finger swipe down shows
the Esc/Ctrl/Alt/arrow key bar KiCad needs. Enable Fullscreen and "Hide display cutout" there too.

Android 12+: if sessions get killed in the background, disable the phantom process killer
(Android 14+: Developer options -> "Disable child process restrictions";
 Android 12/13: adb shell settings put global settings_enable_monitor_phantom_procs false).
If the canvas is slow or blank: KiCad Preferences -> Graphics -> "Fallback" (Cairo) graphics.
EOF
}

uninstall() {
  step "Uninstalling"
  rm -f "$BIN"/kicad-start "$BIN"/kicad-stop "$BIN"/kicad-shell "$BIN"/kicad-cli "$BIN"/kicad-pip "$BIN"/kicad-plugin
  rm -f "$SHORTCUTS/KiCad" "$SHORTCUTS/KiCad-Stop"
  rm -rf "$CONF_DIR"
  if [ -d "$ROOTFS" ]; then
    read -r -p "Delete the $DISTRO guest (KiCad install)? Your Internal storage/KiCad folder is kept. [y/N] " a
    [ "$a" = y ] && proot-distro remove "$DISTRO"
  fi
  ok "removed"
}

update() {
  step "Updating KiCad in $DISTRO"
  proot-distro login "$DISTRO" --shared-tmp -- bash -c 'apt-get update && apt-get -y upgrade'
  ok "updated"
}

case "${1:-}" in
  -h|--help) usage ;;
  --uninstall) uninstall ;;
  --update) update ;;
  "")
    preflight; install_termux_packages; setup_storage; install_distro
    write_config; guest_setup; install_launchers; verify; finish ;;
  *) usage; exit 1 ;;
esac

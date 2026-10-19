#!/usr/bin/env bash
# Simulates Termux with stub commands and runs the installer + launcher end to end. No network, no root.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" PREFIX="$T/usr" TERMUX_VERSION=sim
STUB="$T/stubs"; LOG="$T/calls.log"; GUEST="$T/guest-root"
mkdir -p "$HOME" "$PREFIX/bin" "$PREFIX/tmp/.X11-unix" "$STUB" "$GUEST/etc/xdg/openbox"
cat > "$GUEST/etc/xdg/openbox/rc.xml" <<'X'
<openbox_config><applications>
  <!-- example -->
</applications></openbox_config>
X
ln -s "$(command -v bash)" "$PREFIX/bin/bash"
export PATH="$PREFIX/bin:$STUB:$PATH" LOG GUEST STUB
for n in pkg termux-wake-lock termux-wake-unlock am apt-get; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$LOG"\n' "$n" > "$STUB/$n"; chmod +x "$STUB/$n"
done
cat > "$STUB/termux-setup-storage" <<'X'
#!/usr/bin/env bash
mkdir -p "$HOME/storage/shared"; echo "termux-setup-storage" >> "$LOG"
X
cat > "$STUB/termux-x11" <<'X'
#!/usr/bin/env bash
echo "termux-x11 $*" >> "$LOG"
python3 -c "import socket,os,time;s=socket.socket(socket.AF_UNIX);s.bind(os.environ['PREFIX']+'/tmp/.X11-unix/X0');time.sleep(3)" &
X
cat > "$STUB/dpkg-query" <<'X'
#!/usr/bin/env bash
echo "9.0.1+dfsg-2"
X
cat > "$STUB/kicad" <<'X'
#!/usr/bin/env bash
echo "kicad $* DISPLAY=$DISPLAY GL=${LIBGL_ALWAYS_SOFTWARE:-} SCALE=$GDK_SCALE NOAT=$NO_AT_BRIDGE" >> "$LOG"
X
cat > "$STUB/kicad-cli" <<'X'
#!/usr/bin/env bash
echo "9.0.1"
X
cat > "$STUB/dbus-launch" <<'X'
#!/usr/bin/env bash
shift; exec "$@"
X
cat > "$STUB/openbox-session" <<'X'
#!/usr/bin/env bash
echo openbox-session >> "$LOG"
X
cat > "$STUB/proot-distro" <<'X'
#!/usr/bin/env bash
echo "proot-distro $*" >> "$LOG"
case "$1" in
  install) mkdir -p "$PREFIX/var/lib/proot-distro/installed-rootfs/$2" ;;
  login)
    shift; shared_tmp=0; binds=()
    shift   # distro
    while [ "$1" != -- ]; do [ "$1" = --bind ] && binds+=("$2") && shift; shift; done
    shift
    # simulate guest: HOME is a fake root, binds become symlinks
    export HOME="$GUEST/root"; mkdir -p "$HOME"
    for b in "${binds[@]}"; do src="${b%%:*}"; dst="$GUEST${b#*:}"; mkdir -p "$(dirname "$dst")"; ln -sfn "$src" "$dst"; done
    args=(); for a in "$@"; do a="${a//\/tmp\//$PREFIX/tmp/}"; args+=("${a//\/root\//$GUEST/root/}"); done
    PATH="$STUB:/usr/bin:/bin" OPENBOX_RC="$GUEST/etc/xdg/openbox/rc.xml" exec "${args[@]}" ;;
esac
X
chmod +x "$STUB"/*

echo "### install"; timeout 60 bash "$HERE/install.sh" >"$T/install.out" 2>&1 || { cat "$T/install.out"; exit 1; }
tail -n 22 "$T/install.out"
echo "### assertions"
chk() { eval "$2" && echo "PASS $1" || { echo "FAIL $1"; FAIL=1; }; }
FAIL=0
for f in kicad-start kicad-stop kicad-shell kicad-cli kicad-pip kicad-plugin; do chk "$f installed+exec" "[ -x '$PREFIX/bin/$f' ]"; chk "$f syntax" "bash -n '$PREFIX/bin/$f'"; done
chk "absolute shebang" "head -1 '$PREFIX/bin/kicad-start' | grep -q '^#!$PREFIX/bin/bash'"
chk "shortcuts" "[ -x '$HOME/.shortcuts/KiCad' ] && [ -x '$HOME/.shortcuts/KiCad-Stop' ]"
chk "android folders" "[ -d '$HOME/storage/shared/KiCad/projects' ] && [ -d '$HOME/storage/shared/KiCad/scripts/plugins' ]"
chk "config env" "grep -q KICAD_DISTRO=debian '$HOME/.config/kicad-termux/env'"
chk "openbox maximize rule" "grep -q '<maximized>yes' '$GUEST/root/.config/openbox/rc.xml'"
chk "plugins symlink" "[ -L '$GUEST/root/.local/share/kicad/9.0/scripting/plugins' ]"
chk "ipc plugins symlink" "[ -L '$GUEST/root/.local/share/kicad/9.0/plugins' ]"
chk "Documents/KiCad symlink" "[ -L '$GUEST/root/Documents/KiCad' ]"
chk "x11-repo before x11 pkgs" "grep -n 'x11-repo' '$LOG' | head -1 | grep -q pkg"
chk "apt installs kicad" "grep -q 'apt-get install.*kicad' '$LOG'"
chk "idempotent re-run" "bash '$HERE/install.sh' >'$T/again.out' 2>&1"
echo "### launcher"; : > "$LOG"
kicad-start /root/KiCad/projects/demo/demo.kicad_pro
grep -E 'termux-x11|^am|kicad |openbox|wake' "$LOG"
chk "launcher started X + kicad with project arg" "grep -q 'demo.kicad_pro DISPLAY=:0 GL=1' '$LOG'"
chk "launcher silenced AT-SPI" "grep -q 'NOAT=1' '$LOG'"
chk "launcher logs to file" "[ -f '$HOME/.cache/kicad-termux/last.log' ]"
mkdir -p "$T/srcplug/myplug" && echo "print(1)" > "$T/srcplug/myplug/__init__.py" && (cd "$T/srcplug" && zip -qr ../myplug.zip myplug 2>/dev/null || python3 -c "import shutil;shutil.make_archive('../myplug','zip','.')")
chk "kicad-plugin add zip" "kicad-plugin add '$T/myplug.zip' myplug >/dev/null && [ -e '$HOME/storage/shared/KiCad/scripts/plugins/myplug' ]"
chk "kicad-plugin add --ipc" "kicad-plugin add '$T/myplug.zip' myipc --ipc >/dev/null && [ -e '$HOME/storage/shared/KiCad/scripts/ipc-plugins/myipc' ]"
chk "kicad-plugin list" "kicad-plugin list | grep -q myplug"
chk "kicad-plugin remove" "kicad-plugin remove myplug >/dev/null && [ ! -e '$HOME/storage/shared/KiCad/scripts/plugins/myplug' ]"
chk "uninstall keeps android folder" "echo n | bash '$HERE/install.sh' --uninstall >/dev/null 2>&1 && [ -d '$HOME/storage/shared/KiCad' ] && [ ! -e '$PREFIX/bin/kicad-start' ]"
[ "$FAIL" = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }

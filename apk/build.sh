#!/usr/bin/env bash
# Builds build/KiCadLauncher.apk with the plain Android SDK tools (no Gradle, no downloads).
# Needs: Android SDK (platform android-34, build-tools 34.0.0), JDK 17+, zip.
# Signing: uses apk/debug.keystore (created on first build). Updating an installed APK requires the same key,
# so keep your keystore; set KEYSTORE=/path to use another one.
set -euo pipefail
cd "$(dirname "$0")"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
BT="$SDK/build-tools/${BUILD_TOOLS:-34.0.0}"
JAR="$SDK/platforms/android-34/android.jar"
[ -d "$BT" ] || { echo "Missing $BT (set BUILD_TOOLS=<version> or ANDROID_HOME)"; exit 1; }
[ -f "$JAR" ] || { echo "Missing $JAR (install platform android-34)"; exit 1; }
# Use $JAVA_HOME if set; otherwise whatever java is on PATH (JDK 17+ works).
[ -n "${JAVA_HOME:-}" ] && export PATH="$JAVA_HOME/bin:$PATH"
OUT=build; rm -rf "$OUT"; mkdir -p "$OUT/classes" assets
cp ../install.sh assets/install.sh

"$BT/aapt2" compile --dir res -o "$OUT/res.zip"
"$BT/aapt2" link -o "$OUT/base.apk" -I "$JAR" --manifest AndroidManifest.xml "$OUT/res.zip" \
  -A assets --min-sdk-version 26 --target-sdk-version 34 --version-code "${VERSION_CODE:-4}" --version-name "${VERSION_NAME:-0.4}" \
  --java "$OUT/gen"
javac --release 8 -Xlint:-options -d "$OUT/classes" -classpath "$JAR" \
  $(find java "$OUT/gen" -name '*.java')
"$BT/d8" --lib "$JAR" --min-api 26 --output "$OUT" $(find "$OUT/classes" -name '*.class')
( cd "$OUT" && zip -q -j base.apk classes.dex )
"$BT/zipalign" -f -p 4 "$OUT/base.apk" "$OUT/aligned.apk"

KS="${KEYSTORE:-debug.keystore}"
[ -f "$KS" ] || keytool -genkeypair -keystore "$KS" -storepass android -keypass android -alias debug \
  -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=KiCad Launcher Debug" >/dev/null 2>&1
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$OUT/KiCadLauncher.apk" "$OUT/aligned.apk"
"$BT/apksigner" verify --print-certs "$OUT/KiCadLauncher.apk" | head -2
ls -lh "$OUT/KiCadLauncher.apk"

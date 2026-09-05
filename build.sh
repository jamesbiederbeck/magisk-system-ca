#!/usr/bin/env bash
# Build a redistributable Magisk module that installs a given CA certificate
# into the Android system trust store (/system/etc/security/cacerts) via
# Magisk's magic-mount overlay.
#
# Usage: ./build.sh <path-to-ca.pem> [module-id]
#
# Output: dist/<module-id>/            (unpacked module, for manual install)
#         dist/<module-id>.zip         (flashable via Magisk app -> Install from storage)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA_PEM="${1:?Usage: $0 <path-to-ca.pem> [module-id]}"

if [ ! -f "$CA_PEM" ]; then
  echo "error: CA file not found: $CA_PEM" >&2
  exit 1
fi

if ! openssl x509 -in "$CA_PEM" -noout >/dev/null 2>&1; then
  echo "error: $CA_PEM is not a valid PEM certificate" >&2
  exit 1
fi

HASH="$(openssl x509 -inform PEM -subject_hash_old -in "$CA_PEM" -noout)"
SUBJECT="$(openssl x509 -in "$CA_PEM" -noout -subject -nameopt RFC2253 | sed 's/^subject=//')"
MODULE_ID="${2:-system-ca-${HASH}}"
AUTHOR="${USER:-unknown}"

DIST="$SCRIPT_DIR/dist/$MODULE_ID"
rm -rf "$DIST"
mkdir -p "$DIST/META-INF/com/google/android"
mkdir -p "$DIST/system/etc/security/cacerts"

cp "$SCRIPT_DIR/META-INF/com/google/android/update-binary" "$DIST/META-INF/com/google/android/update-binary"
cp "$SCRIPT_DIR/META-INF/com/google/android/updater-script" "$DIST/META-INF/com/google/android/updater-script"
chmod 755 "$DIST/META-INF/com/google/android/update-binary"

# Re-emit as clean PEM (strips any trailing junk/comments in the input file)
openssl x509 -in "$CA_PEM" > "$DIST/system/etc/security/cacerts/${HASH}.0"

sed \
  -e "s/__MODULE_ID__/${MODULE_ID}/" \
  -e "s/__CA_SUBJECT__/${SUBJECT}/" \
  -e "s/__AUTHOR__/${AUTHOR}/" \
  -e "s#__CA_FILE__#$(basename "$CA_PEM")#" \
  "$SCRIPT_DIR/module.prop.template" > "$DIST/module.prop"

( cd "$DIST" && zip -r -X "../${MODULE_ID}.zip" . -x '.*' >/dev/null )

echo "Built module: $MODULE_ID"
echo "  CA subject:   $SUBJECT"
echo "  cacerts hash: ${HASH}.0"
echo "  Unpacked dir: $DIST"
echo "  Flashable zip: $SCRIPT_DIR/dist/${MODULE_ID}.zip"
echo
echo "Install (manual, adb root):"
echo "  adb push $DIST /data/local/tmp/${MODULE_ID}"
echo "  adb shell su -c 'cp -r /data/local/tmp/${MODULE_ID} /data/adb/modules/${MODULE_ID}'"
echo "  adb shell su -c 'chown -R 0:0 /data/adb/modules/${MODULE_ID}'"
echo "  adb shell su -c 'find /data/adb/modules/${MODULE_ID} -type d -exec chmod 755 {} +'"
echo "  adb shell su -c 'find /data/adb/modules/${MODULE_ID} -type f -exec chmod 644 {} +'"
echo "  adb shell su -c 'chmod 755 /data/adb/modules/${MODULE_ID}/META-INF/com/google/android/update-binary'"
echo "  adb reboot"
echo
echo "Install (Magisk app): copy ${MODULE_ID}.zip to the device, Magisk app -> Modules -> Install from storage, reboot."

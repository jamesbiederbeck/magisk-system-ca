# magisk-system-ca

A tiny Magisk module generator that installs a CA certificate into Android's
**system** trust store (`/system/etc/security/cacerts/`), using Magisk's
magic-mount overlay so it works on `dm-verity`/AVB-locked devices without
ever touching the real `/system` partition.

## Why this exists

On a verity-protected device, `/system` is genuinely read-only at the block
layer — `mount -o rw,remount /system` fails with `'/dev/root' is read-only`,
not a permission error. Editing `/system/etc/security/cacerts/` directly is
not an option.

Android's own default trust manager (`android.security.net.config.RootTrustManager`)
only trusts **system** CAs by default for apps targeting a modern API level —
user-added CAs (`Settings > Security > Install from storage`) are ignored by
most apps unless they explicitly opt in via a `network_security_config.xml`.
So getting a self-signed/private CA trusted system-wide for TLS interception
work requires landing it in the system store specifically.

Magisk solves this without touching the real partition: at boot, before most
of userspace starts, it overlays module files onto the live mount namespace.
The physical `/system` block device is never written, so the verity Merkle
tree still matches and boot proceeds normally — but every process sees the
overlaid files layered on top, correctly labeled
(`u:object_r:system_file:s0`) so SELinux doesn't reject them either.

This is the standard, well-established technique for adding a CA cert
system-wide on a rooted, verity-enabled Android device (the same approach
used to make tools like mitmproxy/Burp work system-wide against apps that
don't do their own certificate pinning).

## What this does *not* do

It does **not** bypass application-level certificate pinning. If an app
pins a specific certificate or public-key hash in its own code (e.g. OkHttp
`CertificatePinner`, a custom `X509TrustManager`, or a native SPKI-hash
comparison), installing a CA here has no effect on that app's connections —
pinned apps validate the presented certificate against their own hardcoded
expectation, not the system trust store. This tool only affects apps that
rely on the platform's default trust manager.

## Usage

```
./build.sh <path-to-ca.pem> [module-id]
```

This produces:

- `dist/<module-id>/` — the unpacked module (for manual `adb push` install)
- `dist/<module-id>.zip` — a flashable zip for the Magisk app's
  "Install from storage"

The module id defaults to `system-ca-<subject_hash_old>`, so building
against different CAs produces distinct, coexisting modules.

### Manual install (adb, device already rooted with Magisk)

`build.sh` prints the exact commands, but in short:

```
adb push dist/<module-id> /data/local/tmp/<module-id>
adb shell su -c 'cp -r /data/local/tmp/<module-id> /data/adb/modules/<module-id>'
adb shell su -c 'chown -R 0:0 /data/adb/modules/<module-id>'
adb shell su -c 'find /data/adb/modules/<module-id> -type d -exec chmod 755 {} +'
adb shell su -c 'find /data/adb/modules/<module-id> -type f -exec chmod 644 {} +'
adb shell su -c 'chmod 755 /data/adb/modules/<module-id>/META-INF/com/google/android/update-binary'
adb reboot
```

Ownership/permission matter: Magisk's magic-mount preserves whatever you
set on the module's files, and mismatched perms on system-path files can
cause boot problems on some builds. `root:root`, `644` on files, `755` on
directories (and on `update-binary`) matches what real system files look
like.

### Magisk app install

Copy the generated `.zip` to the device, open the Magisk app, go to
Modules → Install from storage, pick the zip, reboot.

### Verifying it took

After reboot:

```
adb shell su -c 'ls -laZ /system/etc/security/cacerts/ | grep <hash>'
```

You should see the cert file with SELinux context
`u:object_r:system_file:s0`, identical to the real system certs around it.

### Uninstall

Delete `/data/adb/modules/<module-id>/` (or disable/remove it from the
Magisk app's Modules list) and reboot.

## Provenance

Built and verified against a rooted Meta Quest 1 ("monterey"), Magisk
30.7, Android 10 (SDK 29). Confirmed end-to-end against a real system
service (`com.oculus.deviceauthserver`) that uses the platform's default
`HttpsURLConnection`/`RootTrustManager` with no pinning: before installing
the CA, a self-signed test certificate failed with
`CertPathValidatorException: Trust anchor for certification path not
found`; after installing it (and reissuing the test cert with a matching
hostname), the same request passed TLS validation entirely and reached the
test server (`Unexpected response code 404` — a real HTTP round trip, not
a TLS failure).

## Security notes

- Only use this on devices you own or are explicitly authorized to test.
- Installing a CA into the system trust store weakens TLS validation
  system-wide for every non-pinning app on the device. Don't leave a
  test/throwaway CA installed longer than you need it.
- Keep the CA's private key off the device and off anything you didn't
  generate yourself. This module only ever needs the public certificate
  (`.pem`) — never bundle a private key into the module.

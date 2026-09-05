# example: quest_mitm_ca

A real module built with `../../build.sh`, included as a concrete worked
example rather than a template.

## What it is

This trusts a self-signed test CA (`CN=graph.facebook-hardware.com`,
EC P-256, self-signed) issued for a sandboxed `uhttpd` instance on a lab
OpenWrt router. It was used to confirm, end to end, that
`com.oculus.deviceauthserver`'s `graph.facebook-hardware.com` login flow
on a Meta Quest 1 has **no application-level certificate pinning** — it
relies entirely on the platform's default `RootTrustManager`.

Before installing this module, that request failed with:

```
javax.net.ssl.SSLHandshakeException: java.security.cert.CertPathValidatorException:
Trust anchor for certification path not found.
```

After installing it (plus a DNS override on the lab router pointing
`graph.facebook-hardware.com` at the router itself, and a matching
hostname on the test cert), the same request passed TLS validation
entirely and reached the test server:

```
Unexpected response code 404 for https://graph.facebook-hardware.com:443/login_request
```

A `404` there is a real HTTP round-trip through a fully-negotiated TLS
session — proof the interception worked, not a TLS failure.

## Should you install this exact module?

Only if you specifically want to trust *this* CA, e.g. to reproduce the
above test against your own sandboxed `graph.facebook-hardware.com`
stand-in. Its private key lives only on the lab router that issued it and
is not (and will never be) included here — this directory only ever
contains the public certificate, which is all a system-trust-store module
needs.

For your own target host/CA, run `build.sh` against your own certificate
instead of reusing this one.

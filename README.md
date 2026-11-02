# quire-dist

Signed builds of [Quire](https://github.com/barnabas-szekeres/quire) and its apps for the reMarkable
Paper Pure. The sources are private; only what the tablet downloads is published here.

## Install Quire

Turn on Developer Mode on the tablet (Settings → General → Software → Advanced → Developer mode; it
resets the tablet to factory settings, so sync your notebooks first), connect it to your computer
with USB, and run on the computer (macOS or Linux):

```sh
curl -fsSL https://barnabas-szekeres.github.io/quire-dist/install.sh | bash
```

It asks for the tablet's address (`10.11.99.1` over USB) and its SSH password (Settings → General →
About → Copyrights and licenses, under "GPLv3 Compliance"), and installs the latest Quire. Run it
again to update Quire, and after every reMarkable software update, which takes Quire off.

## What is here

- **Releases**: one per app version, tagged `<app>-v<version>` (e.g. `remailable-v1.0.0`), each with
  `app.tar.zst`, its minisign signature `app.tar.zst.minisig`, and `manifest.json`. Quire's own
  (`quire-v<version>`) also has `quire-rmppure`, the bundle's `quire` on its own, which the
  installer runs on a tablet without Quire to install the bundle with (checked against
  `SHA256SUMS`).
- **Index**: `v1/index.json` on GitHub Pages, signed with the index key, lists every app and its latest
  release. Quire reads it to find updates and to fill the App Store.
- **Installer**: `install.sh`, served from GitHub Pages next to the index.

Check a bundle by hand with `minisign -Vm app.tar.zst -P <publisher key>`.

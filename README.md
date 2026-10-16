# quire-dist

Signed builds of [Quire](https://github.com/barnabas-szekeres/quire) and its apps for the reMarkable
Paper Pure. The sources are private; only what the tablet downloads is published here.

- **Releases**: one per app version, tagged `<app>-v<version>` (e.g. `remailable-v1.0.0`), each with
  `app.tar.zst`, its minisign signature `app.tar.zst.minisig`, and `manifest.json`.
- **Index**: `v1/index.json` on GitHub Pages, signed with the index key, lists every app and its latest
  release. Quire reads it to find updates and to fill the App Store.

Check a bundle by hand with `minisign -Vm app.tar.zst -P <publisher key>`.

# MargyT iOS adapter (experimental)

Native UIKit adapter that injects the MargyT mod menu into the TikTok iOS app.
Targets TikTok **46.9.0** (`com.zhiliaoapp.musically`) only — internal class names
change between releases and other versions are refused by the packager.

## Build (macOS)

Requires Xcode and a **decrypted** TikTok 46.9.0 IPA supplied by the user
(not committed to the repo).

```sh
python3 ios/build.py --ipa /path/to/decrypted.ipa --output build/ios/MargyT-unsigned.ipa
```

`--sdk`, `--clang`, `--linker` are auto-detected via `xcrun` on macOS.
The script compiles `MargyT.dylib` (arm64, iOS 15+), adds a
`@executable_path/Frameworks/MargyT.dylib` load command to the app executable,
copies `Countries.plist`, strips `_CodeSignature`/`embedded.mobileprovision`,
and writes a new unsigned IPA. The input file is never modified.

## Sign

```sh
# re-sign the dylib and the whole .app with your own certificate
codesign -fs "Apple Development: you@example.com" Payload/TikTok.app/Frameworks/MargyT.dylib
codesign -fs "Apple Development: you@example.com" --deep Payload/TikTok.app
zip -r signed.ipa Payload
```

or use your usual sideloading flow (SideStore/AltStore/esign/fastlane resign).

## Entry points

- TikTok Settings -> MargyT row (and navigation-bar button).
- LIVE entrance button opens the menu when "Открывать по кнопке эфира" is on;
  otherwise it calls the original handler.

## Status

Not verified on a physical device. iOS 27 compatibility is unconfirmed — newer
APIs are used only through runtime availability checks. Unsupported Android
features (plugins, signed patches, streak automation, badge server, updater)
are listed in the menu as unavailable rather than silently faked.

## Tests

```sh
python3 -m unittest discover tests
```

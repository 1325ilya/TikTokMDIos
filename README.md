# TikTokMDIos

Experimental MargyT mod adapter for TikTok iOS (version 46.9.0 only).

- `ios/` — Objective-C/UIKit dylib sources and the `build.py` packager.
- `tests/` — offline Python tests for the Mach-O patcher and IPA packager.

Build on macOS with Xcode: see [ios/README.md](ios/README.md). A decrypted
TikTok 46.9.0 IPA is required as input and must not be committed.

```sh
python3 ios/build.py --ipa decrypted.ipa --output build/ios/MargyT-unsigned.ipa
```

The output is unsigned — re-sign with your own certificate before installing.
Not verified on a physical device.

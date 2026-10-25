# Download SwiftDrop directly

## Android — no ZIP extraction

**[Download SwiftDrop-0.3.0-android-debug.apk](https://github.com/wwwadeesaushen7/SwiftDrop/raw/refs/heads/main/downloads/SwiftDrop-0.3.0-android-debug.apk)**

- Size: **229,402,098 bytes** (about **229.4 MB**).
- Android **10 or newer**. Debug-signed test build.
- Open the downloaded `.apk` on Android to install it. GitHub may show a Git LFS notice: use **Download** / **Download raw file**.
- APK SHA-256: `84827102f126c788d65973a8c56e07536cb028510c1e68d4ffcba8d4500b752b`.
- Physical Android-to-Windows operation still needs device testing; see the validation record.

Version **0.3.0** includes **GitHub push and pull**, including Git LFS downloads. See [how to upload your files](../docs/GITHUB_UPLOAD.md). Older APKs and ZIPs remain available for previous links; use 0.3.0 for pull support.

## All ordinary files

- **[Every file: individual download, size and purpose](FILES.md)**.
- **[Mobile/PC usage guide, including the folders in your screenshot](../docs/FILE_GUIDE.md)**.
- **[Browse the source tree](https://github.com/wwwadeesaushen7/SwiftDrop)**. Source files are already stored individually.
- **[Checksums](SHA256SUMS.txt)**.

To get the complete project as normal files on PC, install Git and Git LFS, then:

```powershell
git lfs install
git clone https://github.com/wwwadeesaushen7/SwiftDrop.git
cd SwiftDrop
git lfs pull
```

Use [the main build instructions](../README.md) to compile the Windows app. There is no verified ready-made Windows installer here. The `windows/` folder is its source/build integration; `packaging/swiftdrop.iss` is the installer recipe.

## Earlier optional compressed packages

These are kept so previous download links continue to work. You can use the direct APK and individual source files above instead.

- [Earlier Android APK ZIP](https://github.com/wwwadeesaushen7/SwiftDrop/raw/refs/heads/main/downloads/SwiftDrop-0.1.0-android-debug.zip).
- [Earlier source ZIP](https://github.com/wwwadeesaushen7/SwiftDrop/raw/refs/heads/main/downloads/SwiftDrop-source.zip). Clone the repository for the latest documentation and files.

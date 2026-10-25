# Download SwiftDrop directly

## Android — no ZIP extraction

**[Download SwiftDrop-0.2.0-android-debug.apk](https://github.com/wwwadeesaushen7/SwiftDrop/raw/refs/heads/main/downloads/SwiftDrop-0.2.0-android-debug.apk)**

- Size: **203,629,234 bytes** (about **203.6 MB**).
- Android **10 or newer**. Debug-signed test build.
- Open the downloaded `.apk` on Android to install it. GitHub may show a Git LFS notice: use **Download** / **Download raw file**.
- APK SHA-256: `01068985aa79bda507be269c6c17aceb7324b7dbbb9e12ab7e27b93dd2be4c6e`.
- Physical Android-to-Windows operation still needs device testing; see the validation record.

Version **0.2.0** includes **Push to GitHub**. See [how to upload your files](../docs/GITHUB_UPLOAD.md). The older 0.1.0 APK and ZIPs remain available but do not contain this feature.

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

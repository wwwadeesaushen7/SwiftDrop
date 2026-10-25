# Download SwiftDrop directly

## Windows PC

The repository-root `SwiftDrop.zip` contains the older Windows **0.2.0+2** app (verified from its executable resource). Use the version-checked Windows download/status link below for 0.3.0.

**[Download SwiftDrop-0.3.0-windows-x64-setup.exe — 12.1 MB](https://github.com/wwwadeesaushen7/SwiftDrop/raw/refs/heads/main/downloads/SwiftDrop-0.3.0-windows-x64-setup.exe)**

The Windows build, tests and installer version checks passed in [run 40194019053](https://github.com/wwwadeesaushen7/SwiftDrop/actions/runs/40194019053). The downloaded installer was independently checked: native file version **0.3.0.0**, compiled app **0.3.0.3**, size **12,081,004 bytes**. [Build information and SHA-256](WINDOWS.md).

Close the older SwiftDrop app, install this setup EXE, and launch SwiftDrop from Start. The menu should show **GitHub files → Push files / Pull files**. Flutter and C++ development tools are not needed to install it. This is an unsigned development build; physical-device transfer validation is still required.

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

Use [the Windows download status](WINDOWS.md) to get the checked installer, or [the main build instructions](../README.md) to compile it yourself. The `windows/` folder is source/build integration; `packaging/swiftdrop.iss` is the installer recipe.

## Earlier optional compressed packages

These are kept so previous download links continue to work. You can use the direct APK and individual source files above instead.

- [Earlier Android APK ZIP](https://github.com/wwwadeesaushen7/SwiftDrop/raw/refs/heads/main/downloads/SwiftDrop-0.1.0-android-debug.zip).
- [Earlier source ZIP](https://github.com/wwwadeesaushen7/SwiftDrop/raw/refs/heads/main/downloads/SwiftDrop-source.zip). Clone the repository for the latest documentation and files.

# SwiftDrop

**[Windows PC installer and version-checked build status](downloads/WINDOWS.md)** — expected current version **0.3.0**. A successful Windows build publishes the setup EXE directly; pending/failed builds are shown explicitly.

**[Download the Android APK directly — no ZIP extraction](https://github.com/wwwadeesaushen7/SwiftDrop/raw/refs/heads/main/downloads/SwiftDrop-0.3.0-android-debug.apk)** · **[Mobile/PC usage and file guide](docs/FILE_GUIDE.md)** · **[Every file: purpose and individual download](downloads/FILES.md)**.

The APK is a 229.4 MB debug test build for Android 10+. All source files are also available individually in this repository; use Git and Git LFS to download the full project as normal files.

Private local file sharing in Flutter/Dart, with Android and Windows as the first targets.
Nearby sharing needs no cloud storage or account. Devices must be able to reach each other on a trusted LAN/hotspot. Optional **GitHub files** supports push and pull over the internet. Public pulls work without a token; pushes and private pulls use your own repository token.

**Development build, not a certified production release.** See [validation status](docs/VALIDATION.md) for checks actually run and remaining release gates. Features described below are implemented in source; platform behavior must pass the checklist before release.

## Start here (Windows 10)

1. Install Git for Windows and [Flutter 3.47.8 stable](https://docs.flutter.dev/install). Extract Flutter outside protected directories (for example `C:\dev\flutter`) and add `C:\dev\flutter\bin` to PATH. Dart is included. `.fvmrc` records the selected version.
2. Install Visual Studio 2022, selecting **Desktop development with C++**, MSVC, CMake and a Windows SDK. Visual Studio Code alone does not provide the native compiler.
3. Install current Android Studio. In SDK Manager install Android SDK Platforms 36 and 35 (the JNI dependency uses 35), Android SDK Build-Tools 36.0.0, NDK 28.2.13676358, CMake 3.22.1, and Android SDK Command-line Tools. Install a full Java 21 JDK including `javac` (or use the compatible bundled JDK). A runtime-only Java installation cannot build the app. Set `JAVA_HOME` to its installation, and `ANDROID_HOME` to your Android SDK directory.
4. In PowerShell at the repository root:

```powershell
flutter --version
flutter config --enable-windows-desktop
flutter doctor -v
flutter doctor --android-licenses
flutter pub get
.\tool\check.ps1
flutter run -d windows
```

Use the real OS credential store. Linux needs a running secret-service provider; Windows uses the native secure-storage backend. Do not replace it with plaintext credentials to work around initialization failures.

`pubspec.lock` is provided from validated dependency resolution. Use `flutter pub get --enforce-lockfile` to retain those versions. Update deliberately and rerun all checks; a lockfile alone does not certify a production release.

## Share real files

On the receiver: open **Receive files**, choose the private IPv4 interface, enable receiving, then open **Pair devices**. On the sender: scan its QR on mobile or paste the complete invitation. The receiver must approve pairing. Select files/folders on the sender, choose the paired destination and request transfer. The receiver must separately approve this batch.

Pair each direction separately to exchange files both ways. Invitations contain local IP, port, a SHA-256 certificate fingerprint, a random single-use token and a five-minute expiry. Discovery never grants trust. Manual IP/port pairing also requires the fingerprint and invitation token; there is no insecure IP-only mode.

Files stream in at most 1 MiB upload chunks, one file at a time. Receiver progress is acknowledged only after flush + SQLite checkpoint. Full-file SHA-256 is checked before finalization. Batches receive unique directories, preserving their safe relative paths under `files/`; unfinished payloads stay in `parts/*.part`. No file is automatically opened/executed.

Pause takes effect after the current chunk. Resume in-session or choose **Retry / resume** after interruption/restart. The original source, paired peer and receiver checkpoint must still exist. Re-pair if its IP or port changed. A changed source must start a new batch. Cancel is best effort when the peer is offline: it may retain partial files, but local retry is discarded. Deleting history does not delete received data or checkpoints.

### Two Windows instances on one PC

Build once, then launch separate app profiles from the release directory:

```powershell
flutter build windows --release
$exe = (Resolve-Path .\build\windows\x64\runner\Release\swiftdrop.exe).Path
Start-Process $exe -ArgumentList '--profile=receiver'
Start-Process $exe -ArgumentList '--profile=sender'
```

Profiles isolate SQLite databases, private keys, paired devices and cached SAF selections. Both use the PC's private LAN address and distinct ports. Use a real LAN interface (not loopback) for app UI testing. The automated transport tests explicitly enable a **test-only** loopback bind with `--dart-define=SWIFTDROP_TEST=true`; never use that flag in distribution builds.

## Push and pull GitHub files

Open **Home → GitHub: push / pull files** or **Menu → GitHub files**, then choose **Push files**. Enter your repository, existing branch, optional destination folder and a fine-grained token with **Contents: Read and write**. Choose files, review destination paths and visibility, approve any replacements, then create one commit. Any readable file type is supported up to **100 MiB per file**, **200 files per commit**. Larger files require Git LFS outside SwiftDrop. Token storage is optional and uses the OS vault.

Choose **Pull files** to browse an existing branch/folder, select files and download into a new local batch directory. Public pulls can be anonymous; private pulls require Contents read permission. Git LFS downloads resolve original content and verify SHA-256. Pulls preserve existing local files; Android provides Export to Downloads.

See [GitHub push/pull instructions and limitations](docs/GITHUB_UPLOAD.md). API integration is covered by local HTTP tests; live account downloads remain a manual validation step. For offline sharing between PCs, follow [PC-to-PC instructions](docs/PC_TO_PC.md).

## Android APK

Connect a physical Android 10+ device with USB debugging, or use an emulator for initial UI checks:

```powershell
flutter devices
flutter run -d <android-device-id>
flutter build apk --debug
# build\app\outputs\flutter-apk\app-debug.apk (test only)
```

For a release, generate a private signing keystore outside the checkout:

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\swiftdrop-release.jks" -alias swiftdrop -keyalg RSA -keysize 3072 -validity 10000
```

Create ignored `android/key.properties` locally (never commit it):

```properties
storeFile=C:/Users/YOUR_USER/swiftdrop-release.jks
storePassword=YOUR_LOCAL_KEYSTORE_PASSWORD
keyAlias=swiftdrop
keyPassword=YOUR_LOCAL_KEY_PASSWORD
```

Then `flutter build apk --release`. The signed artifact is `build/app/outputs/flutter-apk/app-release.apk`. Back up the key securely; future updates require it. An unsigned build without `key.properties` is not a distributable release. Validate the APK with your SDK's `apksigner verify --verbose <apk>` and run the two-device checklist before distribution.

Mobile selections use system picker streams, caching non-filesystem content URIs on disk for seekable/resumable uploads. This takes additional storage, never a whole-file RAM buffer. Folder sending is currently desktop-only. Android receives into app documents, then **History → Export verified files to Downloads** copies files through MediaStore with 64 KiB buffers. Original verified files remain; exporting again may create another copy. App documents are removed on uninstall. Receiving directly into an arbitrary SAF folder is not yet implemented.

The manifest declares Internet, network state, multicast and camera access, plus `ACCESS_LOCAL_NETWORK`; runtime requests are made on OS versions 37+. This OS path needs device verification. No broad storage permission or all-files access is requested. No system notifications/foreground service are claimed: keep mobile sessions foregrounded and the screen awake if your OS suspends apps.

## Windows installer

```powershell
flutter build windows --release
# Requires Inno Setup 6 installed separately. Checks the actual EXE version:
.\tool\package-windows.ps1
```

Installer: `build/installer/SwiftDrop-0.3.0-windows-x64-setup.exe`. It installs per user without silently changing firewall rules. Ship the entire Flutter release directory, never just the executable. Provision the Microsoft Visual C++ 2015–2022 x64 Redistributable on target systems. Code-sign both app and installer with your organization certificate before distribution. Store signing credentials outside the repository. Packaging version currently follows `0.3.0`; update the Inno version together with `pubspec.yaml` for releases.

## Linux development

Requires Flutter's Linux desktop dependencies: Clang, CMake, Ninja, pkg-config, GTK 3 development headers, libstdc++ development headers, and `libsecret-1-dev` with a running Secret Service (for example GNOME Keyring). Install the platform packages with your Linux package manager, then:

```sh
flutter config --enable-linux-desktop
flutter pub get
./tool/check.sh
flutter run -d linux
```

The onboarding scripts use the existing `/workspace/SwiftDrop` checkout; no worktree is needed. Processes must be started again in a new task.

## Tests and release gates

```sh
flutter analyze
flutter test --dart-define=SWIFTDROP_TEST=true --reporter expanded
flutter test integration_test/app_test.dart -d <device-id>
# Explicit >4 GiB test, requires at least 6 GiB free disk:
flutter test tool/large_file_check.dart --dart-define=SWIFTDROP_TEST=true --reporter expanded
```

The transport suite opens actual pinned TLS sockets, pairs real endpoints, streams binary data to disk and checks received bytes. It covers consent rejection, unauthorized requests, wrong pins, one-time tokens, multi-chunk and empty files, Unicode paths, restart/resume, duplicate offsets, corruption and cancellation. Unit tests cover framing limits, metadata, hashes and portable path validation. Tests use an in-memory credential vault only for isolated transport testing; the app integration test uses real OS secure storage.

See [manual two-device checks](docs/TESTING.md), [protocol/security](docs/PROTOCOL.md) and [platform status](docs/VALIDATION.md). CI definitions prepare tests, Android debug APK and Windows installer but have not run merely because the YAML exists.

## Layout

- `lib/app`: Material 3 responsive UI and ChangeNotifier application state.
- `lib/core`: bounded metadata parsing, safe paths, wire models, streamed hashing.
- `lib/features/pairing`: OS-stored identity, invitation validation and certificate pinning.
- `lib/features/transfer`: HTTPS receiver, approval, chunk/checkpoint engine and sender.
- `lib/features/github`: optional GitHub push/pull UI, token handling, streamed Git API commits and verified Git/LFS downloads.
- `lib/features/discovery`: native mDNS/Bonjour integration.
- `lib/features/storage`: local SQLite settings, history and checkpoints.
- `android`, `windows`, `linux`: host runners; `packaging`: Windows installer.

## Future platforms and limitations

iOS/macOS host generation and device testing require macOS/Xcode. Shared Dart code is separated from discovery/storage/platform integrations, but these targets are **not ready**. See `docs/APPLE_PLATFORMS.md` for required Bonjour declarations, entitlements and lifecycle checks. Linux host sources are included, not a claim of a tested Linux release. No web target: browsers cannot host this native local TLS receiver.

The initial protocol supports private/link-local IPv4 only, one sending batch per profile, 10,000 files and at most 1 PiB of metadata-declared payload per batch. Empty directories and filesystem metadata/permissions are not transferred. A local adversary with write access to the destination can race filesystem checks; use a destination only your account controls. OS disk writes detect out-of-space errors; there is no portable pre-reservation API yet. TLS encrypts payloads and bearer credentials; network observers can still see service names, addresses and traffic sizes. Production release requires platform testing, resource/abuse hardening and independent security review.

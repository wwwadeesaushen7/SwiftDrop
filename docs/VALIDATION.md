# Validation record — 2026-10-24

This is an initial development implementation, not a production-certified cross-platform release. Checks below ran in the managed Linux environment. A built APK does not establish Android-to-Windows compatibility.

## Passed

- Flutter **3.47.8**, Dart **3.13.7**, official revision `737ba8f885dc774b53b442759999a312c9461e4e`.
- Dependency resolution and `flutter pub get --enforce-lockfile`; `pubspec.lock` is provided. `desktop_drop` **0.8.4** is intentionally pinned because 0.9.2 requires `cross_file` 0.4, incompatible with `file_picker` 13.2.0. No dependency overrides or disabled verification.
- `flutter analyze`: **no issues**.
- Dart formatting: **15 files**, no changes required.
- `flutter test --dart-define=SWIFTDROP_TEST=true --reporter expanded --concurrency=2`: **27 passed, 0 failed, 0 skipped**.
- Real pinned TLS sockets, exact multi-chunk binary bytes on disk, Unicode folders and empty files; rejection/unauthorized/wrong-pin/used-token cases; SQLite restart/resume; hash mismatch; pause/cancel; crash recovery after rename; uncommitted tail truncation; concurrent chunk rejection; authorized reconnection. Test-only credential storage is in memory; production uses OS secure storage.
- Protocol framing limits, metadata, streamed hashes, safe relative paths and large-size metadata.
- Responsive navigation at **390×844** and **1280×800**. A mobile app-bar overflow discovered by testing was fixed.
- Separate stress test: `flutter test tool/large_file_check.dart --dart-define=SWIFTDROP_TEST=true --reporter expanded`: **1 passed**. Transferred **4,294,967,313 bytes** (4 GiB + 17) over real TLS and verified destination length and SHA-256. **6 minutes 54 seconds** here; this is not a Windows/Android benchmark.
- Android SDKs 35/36, build-tools 36.0.0, platform-tools, NDK 28.2.13676358 and CMake 3.22.1 installed. Full Temurin JDK 21.0.13+9 installed and verified against its official SHA-256. Android tools checked against Google's official repository checksum; Gradle wrapper SHA-256 verified and distribution checksum pinned.
- Final `tool/bootstrap-cloud.sh` completed successfully, including pinned Flutter/JDK, Android prerequisites, engine cache and frozen dependency resolution. A subsequent incremental APK rebuild passed in 12.5 seconds.

## Android artifact

**Debug APK build passed.** Artifact: `build/app/outputs/flutter-apk/app-debug.apk` (about 195 MiB). `apksigner verify --verbose` passed with APK Signature Scheme v2, one signer. ZIP CRC verification passed; Flutter and SQLite native libraries are packaged for ARM64, ARMv7 and x86_64.

Manifest verified: `app.swiftdrop`, version `0.1.0+1`, label **SwiftDrop**, minimum SDK **29**, target/compile SDK **36**. No broad storage permission appears in the merged manifest. This is a **debug-signed test APK**, not a production-signed release; no physical-device installation/transfer test has run.

APK SHA-256: `aa1cc2cfd12b773bf1e1df60cdd5288d61b25a68ff786ca6dfa1932e713fed9b`.

Setup failures were resolved without disabling TLS or checksums: removed a conflicting deprecated Android variable; installed a full JDK after discovering runtime-only Java; selected the existing managed system Java trust store for the new JDK; installed SDK 35 for JNI and CMake 3.22.1 for native compilation. The pinned compatible drag-and-drop release still emits a future Kotlin-plugin migration warning. Updating Flutter/packages requires retesting that compatibility.

## Phase status

| Phase | Evidence and outstanding work |
| --- | --- |
| 1: UI/navigation | Analysis and mobile/desktop widget tests pass; native app integration test unrun. |
| 2: Windows transfer | Shared transport passes Linux real-socket tests; Windows runner and isolated app profiles exist. Windows builds and two-instance tests unrun. |
| 3: Android↔Windows | Android selection/export/network-permission integration implemented. APK status above; physical cross-device tests unrun. |
| 4: discovery/security | Pinning, authentication, invitation/consent tests pass. Actual mDNS, QR camera and OS permission behavior unrun. |
| 5: transfer engine | Streaming, >4 GiB, integrity, queue order, pause/cancel, resume and path defenses have automated evidence. Native lifecycle/storage-provider/filesystem cases remain. |
| 6: local state/settings | SQLite and UI implemented; checkpoint restart tested. OS vault, native settings restarts and Android MediaStore export unrun. System notifications/background service are not implemented. |
| 7: packaging | Android status above. Windows build instructions, Inno Setup source and CI recipes exist; no Windows executable/installer has been built here. Production signing needs user-controlled keys. |
| 8: other platforms | Linux runner source exists but native development toolchain is unavailable. Apple hosts/entitlements still need implementation on macOS/Xcode. |

No connected Android device, Windows machine or Apple build host is attached. ADB also attempts a read-only home configuration directory in this sandbox. The Linux desktop toolchain (compiler, GTK/libsecret development headers and configured Secret Service) is unavailable; Android CMake is installed for APK compilation; passing widget tests does not validate native Linux runtime. CI recipes have not run merely because they exist.

## Remaining implementation/release scope

- Mobile folder sending, direct Android SAF receive destinations, OS notifications and supported background lifecycle. Android currently stores received files in app documents and provides explicit streamed History export to Downloads. Keep mobile sessions foregrounded.
- Apple runners, privacy declarations/entitlements, macOS security-scoped bookmarks, iOS Files export.
- IPv6, disk pre-reservation, per-device storage quotas and listener-level abuse limits.
- Native race-resistant filesystem handles against another process modifying the receive directory concurrently; use an account-owned destination.
- Physical-device matrix, installer/upgrades/signing and independent security review before public production release.

See [TESTING.md](TESTING.md). Unchecked manual cases are **unrun**, not passes or expected failures.

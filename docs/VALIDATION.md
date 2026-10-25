# Validation record — updated 2026-10-25

This is an initial development implementation, not a production-certified cross-platform release. Checks below ran in the managed Linux environment. A built APK does not establish Android-to-Windows compatibility.

## Windows installer version correction (2026-10-25)

The user reported receiving an actual **0.2.0** Windows installer after being directed to a generic **SwiftDrop-Windows** Actions artifact. Earlier screenshots established a 0.2.0 Windows build; they did not establish a successful 0.3.0 build. The source and Inno recipe already declare 0.3.0.

A separate **Windows installer (version checked)** workflow now reads the actual compiled EXE's four-part resource version, compares it with `pubspec.yaml`, checks the Inno recipe, packages, and checks the installer resource version. Artifact names contain the version and commit. A separate main-branch publisher verifies metadata, bytes and SHA-256 before committing the exact versioned EXE, checksums and build information into `downloads`. Pull requests cannot publish. Failed builds report failure rather than reusing an older installer. The previous unversioned Windows job is removed to avoid duplicate/confusing builds.

The actual `swiftdrop.exe` inside the owner-uploaded root `SwiftDrop.zip` was inspected with a PE resource reader: its string version is **0.2.0+2**, fixed file version **0.2.0.2**. It is not a 0.3.0 distribution.

Publisher tests cover matching output, corrupt data, older app/installer versions, wrong source commits/build numbers/filenames, and failure reporting. These tests validate publication contracts; the real Windows packaging/build result must be read from [the Windows status page](../downloads/WINDOWS.md), which starts as pending. Do not claim a compiled 0.3.0 Windows installer exists until that workflow succeeds.

The first checked Windows run for commit `4febe7f` reported **failure**: [run 40192426206](https://github.com/wwwadeesaushen7/SwiftDrop/actions/runs/40192426206). Its separate status publisher succeeded and recorded failure in `downloads/windows-build.json`; **no 0.3.0 installer was published**. The GitHub API/logs are blocked in this cloud environment, so the failing step/error must be obtained before fixing or claiming a successful build. PowerShell parsing, source/recipe version agreement, actionlint workflow validation and four publisher tests passed locally; these do not establish Windows compilation.

## GitHub pull update — 0.3.0 (2026-10-25)

- Added **GitHub files → Push files / Pull files**. Browse public repositories anonymously or private repositories with Contents read permission, navigate a pinned commit, select up to 200 files and choose a desktop destination. Downloads stream to unique batch directories, preserve existing local files, verify ordinary Git blob SHA-1 / LFS SHA-256, and discard incomplete batches on cancellation or errors. Android supports app-owned downloads with direct/History export to Downloads.
- Git LFS downloads resolve the original content rather than saving the pointer file. Tokens remain confined to GitHub API/LFS endpoints, storage actions use separate temporary credentials, and unsafe paths/symlinks/submodules/hosts/redirects are rejected. Directories are limited to 1,000 displayed entries; narrower paths can traverse larger ancestors within the metadata limit.
- `flutter analyze`: **no issues**. Formatting checks pass. All **54 tests pass**, 0 failed, 0 skipped in Linux: 39 previous tests plus 15 pull tests. Real loopback HTTP tests cover binary/Unicode/empty downloads, LFS resolution/integrity, public reads, immutable folder navigation, directory limits, source/destination preservation, cancellation, unsafe paths/hosts and history. Widget tests open both modes at 390×844 and 1280×800.
- Android debug APK **0.3.0+3** built successfully (final incremental build 8.9 seconds), **229,402,098 bytes**. APK Signature Scheme v2 and ZIP CRC checks pass; Android minimum 29, target/compile 36. SHA-256: `84827102f126c788d65973a8c56e07536cb028510c1e68d4ffcba8d4500b752b`. This remains a debug-signed development build; physical Android installation/export is unrun here.
- User screenshots showed version 0.2.0's Windows CI job succeeding and its app UI running on Windows. Version 0.3.0 Windows compilation is left to the updated GitHub Actions run; that run is not verified from this environment. Physical Windows-to-Windows file transfer is unrun. Added [PC-to-PC instructions](PC_TO_PC.md).
- Live GitHub REST/LFS downloads through the app are **unrun here** because the cloud network blocks `api.github.com`. No real user token was requested for testing. The download suite exercises actual sockets/file streams against a local API fixture; it does not establish live GitHub authorization or native OS vault/export behavior.
- Pull limitations: files selected from one displayed folder per batch; no recursive folder download, Git working-copy merge, interrupted GitHub download resume, Git LFS upload or Release asset support. GitHub quotas and filesystem limits still apply. See [GitHub instructions](GITHUB_UPLOAD.md).
- Incorporated the repository owner's newer `SwiftDrop.zip` upload before development; that file is preserved unchanged.

The records below refer to earlier versions and their validation at the time.

## GitHub upload update — 0.2.0 (2026-10-25)

- Added **Push to GitHub** with repository/branch/folder selection, fine-grained personal access tokens, optional OS vault persistence/forget, explicit review and replacement approval, bounded streamed binary uploads, cancellation, Git object verification and one non-force branch update per batch. Repository tree metadata caches are bounded to four directories.
- `flutter analyze`: **no issues**. All **39 tests pass** (27 existing + 12 GitHub tests); responsive widget checks now also open the GitHub screen at 390×844 and 1280×800.
- GitHub tests use real loopback HTTP sockets and file streams against an API fixture. **Live GitHub account uploads are unrun:** this environment blocks `api.github.com`. No user token was requested or used for these tests.
- Android debug APK **0.2.0+2** built successfully; final incremental rebuild passed in 10.4 seconds. Size **229,345,457 bytes**; APK signature v2 and ZIP CRC checks passed. Minimum Android SDK 29, target/compile 36. SHA-256: `1edd9cce668208b94031bfcbe738d25e776936fe1625115195714f42e4a07baa`.
- This is a debug-signed development APK, not a production-signed release. Physical Android use, real OS token persistence and Windows compilation/runtime remain unrun. Windows Inno Setup version updated to 0.2.0.
- GitHub uploads require internet, an initialized existing repository and an existing writable branch. Limit 100 MiB per file / 200 files per batch; Git LFS, repository/branch creation and interrupted GitHub upload resume are not implemented. See [instructions and manual checks](GITHUB_UPLOAD.md).

The remaining sections record the original 0.1.0 validation. Its old APK and source archives do not include this update.

## Original 0.1.0 checks: passed

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

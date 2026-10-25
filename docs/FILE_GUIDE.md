# SwiftDrop: which files to use on mobile and PC

The folders in your screenshot contain the developer project. GitHub stores the files; SwiftDrop runs on your device after installation or compilation.

## Choose what you need

| What you want | What to get |
| --- | --- |
| Use SwiftDrop on an Android phone | [Download the APK directly](https://github.com/wwwadeesaushen7/SwiftDrop/raw/refs/heads/main/downloads/SwiftDrop-0.3.0-android-debug.apk). About **229.4 MB**, Android **10+**, debug test build. No outer ZIP or extraction step. |
| Read or edit the source | The normal files in this repository, especially `lib/`. |
| Download the whole project as individual files on Windows | Clone with Git and Git LFS using the commands below. Git creates the folder tree for you. |
| Use SwiftDrop on a Windows PC | Build the Windows app from the full project. No verified ready-made Windows installer is provided here. |
| Use SwiftDrop on an iPhone or Mac | These native targets are still unfinished; an iOS/macOS installer is not provided. |

## Android: use the files in your screenshot

1. Open [the repository](https://github.com/wwwadeesaushen7/SwiftDrop) in your browser. Sign in if GitHub asks, especially if the repository is private.
2. Tap the **downloads** folder shown in your screenshot.
3. Tap **SwiftDrop-0.3.0-android-debug.apk**. This is the new direct installer, without `.zip` at the end.
4. Use GitHub's **Download** / **Download raw file** button (a downward arrow; it can be inside the three-dot menu on a narrow screen). GitHub may show a **Git LFS** notice because this is a large file; choose its Download button. You can also use the direct APK link above.
5. Once the approximately 229.4 MB download finishes, open Android's **Files → Downloads** and tap the APK.
6. If Android requests it, allow installation from the browser or Files app you are using, then tap **Install → Open**.

The `.dart`, `.yaml`, `.cpp` and `.kt` files are source/build files. You use the APK to install the Android app. On iPhone, APK installation is unavailable.

This is a debug-signed development build. Installation and transfers on physical phones still need testing; the automated transport checks ran in Linux. A Play Store production release is not being claimed.

### Send a file after installation

1. Put both devices on the same Wi-Fi or phone hotspot. Internet is not needed for the transfer itself.
2. Receiver: open **Receive files**, select the local network address and enable receiving.
3. Receiver: open **Pair devices** to show a fresh QR invitation.
4. Sender: open **Pair devices → Scan QR**, or paste the receiver's full invitation. Allow camera permission if scanning. The receiver must approve pairing.
5. Sender: open **Send files**, select files and the paired receiver, and request the transfer. Receiver: **Accept**.
6. Keep both apps open while transferring. On Android, use **History → Export verified files to Downloads** to copy completed files to a user-visible Downloads folder.

## Upload your files to GitHub from the app

SwiftDrop **0.3.0** includes **Home → GitHub: push / pull files**. Choose **Push files** to upload. Enter your repository, existing branch and a fine-grained token with Contents read/write access; choose files, review, then commit. Internet is required. Files are limited to 100 MiB each and 200 per commit. Choose **Pull files → Browse files** to select repository files and save them locally; public pulls need no token and private pulls need Contents read access. Git LFS downloads are supported. [Step-by-step GitHub instructions](GITHUB_UPLOAD.md).

## Windows: download every source file without a ZIP

Install **Git for Windows** with **Git LFS**. Git for Windows commonly includes Git LFS; if `git lfs version` is unavailable, install Git LFS from its official site. Then open PowerShell in the folder where you want the project:

```powershell
git lfs install
git clone https://github.com/wwwadeesaushen7/SwiftDrop.git
cd SwiftDrop
git lfs pull
```

If GitHub asks you to sign in, use its browser sign-in flow. These commands download the repository as normal folders/files; no manual archive extraction is needed. `git lfs pull` obtains the actual large APK as well as the ordinary source checkout. To refresh later, inside this folder run:

```powershell
git pull
git lfs pull
```

The APK should be about 229.4 MB. If you instead get a tiny text file beginning `version https://git-lfs.github.com/spec/v1`, it is a Git LFS pointer: run `git lfs pull`, or use GitHub's Download button for the actual APK.

The earlier ZIP downloads remain for existing links, but they are optional. The normal source tree and the new `.apk` are the uncompressed-file route.

### Build and use the Windows app

For Windows 10 development, install **Flutter 3.47.8 stable** and **Visual Studio 2022 → Desktop development with C++**, including MSVC, CMake and a Windows SDK. Flutter must be on PATH. Visual Studio Code is an editor; Visual Studio's native compiler workload is required for this build.

Open PowerShell in the cloned `SwiftDrop` directory, the folder containing `pubspec.yaml`:

```powershell
flutter config --enable-windows-desktop
flutter doctor -v
flutter pub get --enforce-lockfile
flutter build windows --release
Start-Process .\build\windows\x64\runner\Release\swiftdrop.exe
```

Address any **Windows toolchain** errors from `flutter doctor`. Android/Chrome checks are optional when you only build the Windows desktop target. A full JDK and Android SDK are needed if you also build Android APKs; [README.md](../README.md) gives those prerequisites.

The resulting app is `build/windows/x64/runner/Release/swiftdrop.exe`. Keep the **entire Release folder**, including its DLLs and `data` directory, when moving the app to another PC. `packaging/swiftdrop.iss` is an Inno Setup recipe for building an installer, not an installer executable itself. Instructions are in [README.md](../README.md#windows-installer).

Windows compilation and phone-to-PC transfers have not been verified from this Linux task. If compilation fails, keep the error output for diagnosis. A source upload or a green indicator in GitHub is not a substitute for the physical-device checks in [TESTING.md](TESTING.md).

### Download just one ordinary source file

On mobile or PC, open its folder in GitHub, click the file, and use **Download raw file** (downward arrow / three-dot menu). For text shown by **Raw**, save the page/file with its original filename and extension. Use Git clone above when you need the complete folder structure for building.

The [downloadable file index](../downloads/FILES.md) provides individual links, sizes and purposes for every ordinary source file and the direct APK. Existing ZIPs are listed separately as optional older packages.

## What each entry in your screenshot is for

| Entry | Purpose | How you use it |
| --- | --- | --- |
| `.github/workflows/` | GitHub Actions build/test configuration. | GitHub runs these recipes; view progress in the **Actions** tab. |
| `android/` | Android host, permissions, Kotlin integration and Gradle build files. | Flutter uses it to build APKs. |
| `docs/` | Usage, protocol, validation, testing and platform documentation. | Open the Markdown files to read them. |
| `downloads/` | Direct Android APK, file index and checksums; earlier optional ZIPs. | Android users download the `.apk` here. |
| `integration_test/` | Tests that start the native app and exercise navigation. | Developers run them on a configured target device. |
| `lib/` | Main Dart application: screens, networking, discovery, security and storage. | Developers edit this; Flutter compiles it. |
| `linux/` | Linux desktop host/build integration. | Used by Flutter for a future validated Linux build. |
| `packaging/` | Windows installer recipe. | Inno Setup uses it after the Windows app is compiled. |
| `test/` | Automated protocol, transfer and responsive-layout tests. | Run `flutter test --dart-define=SWIFTDROP_TEST=true`. Never use that test-only define for distributed builds. |
| `tool/` | Developer check/setup scripts and the large-file stress test. | Run the relevant script; cloud setup scripts are for the managed Linux environment. |
| `windows/` | Windows C++ runner and desktop build integration. | Flutter uses it to create the `.exe` and companion files. |
| `.fvmrc` | Pinned Flutter SDK version for FVM users. | Helps developers select Flutter 3.47.8. |
| `.gitattributes` | Git LFS rule for the large direct APK. | Git/Git LFS uses it automatically. |
| `.gitignore` | Rules excluding local caches, signing keys and generated outputs from commits. | Git uses it automatically. |
| `README.md` | Main project overview and exact build commands. | Start here when developing/building. |
| `analysis_options.yaml` | Dart analyzer/lint settings. | `flutter analyze` uses it. |
| `pubspec.yaml` | App identity, Flutter assets and dependency requirements. | Flutter reads it to resolve/build the project. |
| `pubspec.lock` | Exact resolved dependency versions. | Keep it for repeatable builds; use `--enforce-lockfile`. |

The **Releases** area on the right of your screenshot is separate from repository files. For this upload, the direct APK is inside **downloads**, so you can get it there without creating a release.

## PC-to-PC sharing

See [the Windows PC-to-PC walkthrough](PC_TO_PC.md): same Wi-Fi/hotspot, receiver enables receiving and copies its invitation, sender pastes and pairs, then sends files with receiver approval. GitHub and internet are not required for the transfer.

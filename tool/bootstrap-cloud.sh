#!/usr/bin/env bash
set -euo pipefail
cd /workspace/SwiftDrop
mkdir -p /workspace/toolchains
if [[ ! -d /workspace/toolchains/flutter/.git ]]; then
  git clone --depth 1 --branch 3.47.8 https://github.com/flutter/flutter.git /workspace/toolchains/flutter
fi
[[ "$(git -C /workspace/toolchains/flutter rev-parse HEAD)" == 737ba8f885dc774b53b442759999a312c9461e4e ]] || {
  echo 'Unexpected Flutter revision; preserve it and resolve the toolchain version explicitly.' >&2; exit 1;
}
if [[ ! -x /workspace/toolchains/jdk/jdk-21.0.13+9/bin/javac ]]; then
  curl --fail --location --retry 2 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13+9/OpenJDK21U-jdk_x64_linux_hotspot_21.0.13_9.tar.gz' -o /tmp/swiftdrop-jdk.tar.gz
  echo 'd7f5d5cf865a2902b70ff549b97586a7d3f234e016f041ab447ea740c7d66d1c  /tmp/swiftdrop-jdk.tar.gz' | sha256sum --check --status
  mkdir -p /workspace/toolchains/jdk
  tar -xzf /tmp/swiftdrop-jdk.tar.gz -C /workspace/toolchains/jdk
fi
source tool/cloud-env.sh
flutter --version
javac -version
flutter precache --android
if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/android" ]]; then
  curl --fail --location --retry 2 https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip -o /tmp/swiftdrop-android-tools.zip
  python3 - <<'PY'
from pathlib import Path
import hashlib, zipfile
archive = Path('/tmp/swiftdrop-android-tools.zip')
hash = hashlib.sha1()
with archive.open('rb') as stream:
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        hash.update(block)
# Google's repository2-3.xml checksum for command-line tools 23.0.
assert hash.hexdigest() == 'e025545c62a8e64c7559119566a569fb1dec5f60', 'Android tools checksum mismatch'
root = Path('/workspace/toolchains/android/cmdline-tools')
root.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(archive) as zip:
    zip.extractall(root)
(root / 'cmdline-tools').rename(root / 'latest')
for binary in (root / 'latest' / 'bin').iterdir():
    binary.chmod(0o755)
PY
fi
"$ANDROID_HOME/cmdline-tools/latest/bin/android" --sdk="$ANDROID_HOME" sdk install 'platforms/android-36' 'platforms/android-35' 'build-tools/36.0.0' 'platform-tools' 'ndk/28.2.13676358' 'cmake/3.22.1'
mkdir -p "$GRADLE_USER_HOME"
if [[ ! -e "$GRADLE_USER_HOME/gradle.properties" ]]; then
  printf 'org.gradle.workers.max=2\norg.gradle.parallel=false\n' > "$GRADLE_USER_HOME/gradle.properties"
fi
flutter pub get --enforce-lockfile

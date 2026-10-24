#!/usr/bin/env bash
# Source this only inside the managed /workspace cloud machine.
export PATH="/workspace/toolchains/flutter/bin:/workspace/toolchains/android/platform-tools:$PATH"
export PUB_CACHE=/workspace/.pub-cache
export FLUTTER_SUPPRESS_ANALYTICS=true
export XDG_CONFIG_HOME=/workspace/.config
export XDG_DATA_HOME=/workspace/.local/share
export ANDROID_HOME=/workspace/toolchains/android
export ANDROID_USER_HOME=/workspace/toolchains/android-user
export GRADLE_USER_HOME=/workspace/toolchains/gradle-user
# Java/Gradle do not automatically honor HTTPS_PROXY. This is the cloud
# runtime's documented proxy; local transfer clients explicitly use DIRECT.
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dhttps.proxyHost=proxy -Dhttps.proxyPort=8080 -Dhttp.proxyHost=proxy -Dhttp.proxyPort=8080 -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts"
export ANALYZER_STATE_LOCATION_OVERRIDE=/workspace/.dart-server
export DASH__SUPPRESS_ANALYTICS=true

export JAVA_HOME=/workspace/toolchains/jdk/jdk-21.0.13+9
export PATH="$JAVA_HOME/bin:$PATH"

# Apple platform bring-up (not completed)

A macOS host with compatible Xcode is required. This repository currently contains Android, Windows and Linux host sources. Do not claim iOS/macOS support before doing these steps and device testing.

On a separate coding task/branch, add host runners with the pinned Flutter SDK (`flutter create --platforms=ios,macos --org app --project-name swiftdrop .`), preserving custom source, pubspec, tests, Android and Windows integrations. Review generated changes; do not run generation blindly over an existing customized checkout.

Add these keys in the iOS and macOS runner Info.plist files (actual host files do not exist yet):

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>SwiftDrop discovers your devices and transfers files directly on your local network.</string>
<key>NSBonjourServices</key>
<array><string>_swiftdrop._tcp</string></array>
<key>NSCameraUsageDescription</key>
<string>Scan a trusted device's SwiftDrop pairing invitation.</string>
```

macOS sandbox entitlements need network client/server access and user-selected file read/write access. Implement and test security-scoped access/bookmark persistence for sources, dropped folders and receive destinations. The current desktop filesystem-path flow is insufficient evidence of durable macOS sandbox access. Verify secure-storage Keychain entitlements and Bonsoir native requirements. iOS files are staged through system-picker streams; implement a user-driven Files export path for completed batches.

Build/simulator checks are not real-device LAN tests. Exercise local-network denial/regrant, Bonjour multicast, QR camera denial, background suspension and large-file disk pressure on physical Apple hardware. Keep the iOS app foregrounded until a supported transfer lifecycle is implemented and tested. Do not enable broad App Transport Security exceptions to bypass the pinned HTTPS transport.

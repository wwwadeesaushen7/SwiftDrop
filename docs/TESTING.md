# Two-device acceptance checklist

Record device models, OS versions, app commit/version, filesystem, network type, source sizes, received hashes, timings and outcome. A box below is a required check, not an assertion it has passed.

## Initial release matrix

- [ ] Windows 10 x64 → Windows 10 x64, separate physical machines.
- [ ] Two isolated profiles on one Windows PC, for development only.
- [ ] Android 10+ → Windows 10 and Windows 10 → Android.
- [ ] Android latest stable, including actual local-network/camera permission flows.
- [ ] Shared router, phone hotspot (phone as sender and as receiver), internet disconnected.
- [ ] Linux physical devices if offering a Linux release.
- [ ] iOS/macOS only after their host runners, entitlements and lifecycle checks exist.

## Trust and privacy

- [ ] Sharing is off on launch; enabling exposes only selected private adapter and advertised port.
- [ ] Receiver discovers device name/platform; no credential appears in mDNS records.
- [ ] Scan QR, verify pinned certificate, approve pairing on receiver, transfer requires a second approval.
- [ ] Paste full invitation while mDNS is blocked; manual IP/port + fingerprint/token connects.
- [ ] Reject pairing/offer; confirm no payload is published.
- [ ] Expired, reused or incorrect invitation and incorrect fingerprint are rejected.
- [ ] Unpaired client cannot offer, query status or write bytes.
- [ ] Revoke incoming pairings, re-enable receiving, confirm old credential is rejected.
- [ ] Disable sharing; previous port stops accepting connections and mDNS announcement disappears.
- [ ] Packet capture confirms encrypted payloads (do not publish captures containing pairing details).

## Files and folders

- [ ] Mix photos, videos, PDFs, audio, ZIP, APK and random binary content; compare SHA-256 on both devices.
- [ ] Select multiple files; Windows drop both files and nested folders.
- [ ] Zero bytes, a one-byte file, >1 MiB chunk boundary and a file >4 GiB on supported filesystems.
- [ ] Unicode and spaces survive; unsafe Windows filenames are rejected clearly.
- [ ] Two independent batches with equal names cannot overwrite each other's files.
- [ ] Two selected sources with colliding relative names are rejected before network transfer.
- [ ] Desktop destination chosen before receiving; insufficient permissions/out-of-space yields a useful error.
- [ ] Android system picker sends a provider-backed content URI without whole-file RAM buffering.
- [ ] Android History export produces the same hashes under Downloads/SwiftDrop, retains originals, never executes files.
- [ ] Empty directories and symlinks are excluded as documented.
- [ ] App stays responsive and memory remains bounded while sending/receiving a very large file.

## Interruptions and state

- [ ] Progress, throughput and ETA reflect acknowledged bytes. Receiver displays final integrity verification.
- [ ] Pause after a chunk, wait, resume: byte count stops and final hash remains correct.
- [ ] Cancel during hashing and upload; no completed-history entry is created for an incomplete batch.
- [ ] Disconnect Wi-Fi, reconnect, pair updated address if needed, retry: confirmed bytes are not resent.
- [ ] Restart both apps: same profiles retain identity, credentials, history and checkpoints.
- [ ] Kill receiver after a payload flush and after final rename: retry recovers with no duplicate bytes.
- [ ] Modify/truncate source between attempts: resume rejects changed manifest or hash mismatch prevents publication.
- [ ] Simulate corrupt chunk: receiver rejects at EOF and resets that file's checkpoint.
- [ ] Fill receiver disk during upload: no false success; fix free space and retry safely.
- [ ] Switch router/hotspot adapter: old listener shuts down; receiving can be enabled on new adapter.
- [ ] Foreground/background tests document actual OS behavior; do not advertise unsupported background transfers.

## UI and packaging

- [ ] Resize desktop through narrow/wide layouts; no overflow; mobile buttons remain touch-friendly.
- [ ] Light/dark/system themes persist; device name/discovery/destination settings persist.
- [ ] QR camera denial has manual fallback; no blanket storage permission is requested.
- [ ] Completed folder can be opened on Windows; received executables never run automatically.
- [ ] Clear history removes only history and leaves files/checkpoints intact.
- [ ] Android signed release APK installs/upgrades on physical devices; signature verified.
- [ ] Windows installer installs/uninstalls on a clean Windows 10 machine; DLL/data assets and VC runtime are present.
- [ ] Private-only Windows firewall rule documented; test refusal and recovery without disabling firewall.
- [ ] Installer and Windows binary signed before public distribution.

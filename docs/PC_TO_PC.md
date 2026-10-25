# Share files from one Windows PC to another

Install SwiftDrop on both PCs. The C++ development tools are needed only if compiling the source yourself; installing a built app does not require them. Use the complete installer or keep the whole extracted Release directory together.

1. Connect **both PCs to the same Wi-Fi/router or phone hotspot**. Internet is not required for nearby transfers. Guest Wi-Fi may isolate devices.
2. On the receiving PC (**PC B**), open **Receive files**, choose its private Wi-Fi/hotspot IPv4 address, and enable receiving. Choose a destination first if desired; disable receiving before changing it in Settings.
3. If Windows Defender Firewall asks, allow SwiftDrop on your trusted **Private network**. Keep the firewall enabled.
4. On PC B, open **Pair devices → Copy invitation**. Share the entire `swiftdrop://…` text privately with PC A (for example through a private message or a USB text file). The invitation expires after five minutes; use **New invitation** if needed. Desktop camera scanning is not implemented, so use the text invitation between PCs.
5. On the sending PC (**PC A**), open **Pair devices**, paste the full invitation and click **Pair securely**. PC B must approve the pairing request.
6. On PC A, open **Send files**, select files or a folder (or drag them into the app), and choose PC B from the paired-device list.
7. Click **Request transfer** on PC A, then **Accept** the incoming batch on PC B. The receiver approves each new transfer.
8. Leave both apps open until completion. On PC B, open **History → Open saved location** to see the verified files. Each batch has its own directory and preserves relative file paths.

To send in the other direction, enable receiving on PC A and pair PC B with PC A’s invitation. Pause/resume and retry use the local transfer engine; GitHub is not involved.

If a connection fails, check that both PCs use the same reachable network, the selected adapter is Wi-Fi/Ethernet rather than a VPN, and Windows permits SwiftDrop’s TCP port shown on Receive. mDNS uses UDP 5353 for discovery; discovery is optional when using a full invitation. Hotspot/client isolation can block device-to-device traffic. Do not open a router port or disable the firewall. See **Connection help** in the app.

The Windows build and app UI were shown running in the user-provided screenshots for version 0.2.0. A physical two-PC transfer has not been observed or tested in this cloud environment. Run the [two-device checklist](TESTING.md) before treating a platform combination as validated.

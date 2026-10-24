# SwiftDrop wire protocol v1

Transport: HTTPS with a locally generated RSA-2048 X.509 certificate. The private key is stored only through OS secure storage. Certificates are pinned by SHA-256 over DER from an out-of-band invitation. The HTTP client uses an empty root store, validates the exact fingerprint for the intended peer and does not follow redirects. No public CA or plaintext fallback is used.

Sharing explicitly binds one selected private IPv4 interface on an ephemeral port. The port is saved for subsequent launches where available. Disabling sharing closes the listener and mDNS activity. No UPnP, router configuration, wildcard listener, cloud relay, arbitrary download endpoint, or automatic file execution exists.

## Pairing and authentication

`swiftdrop://<private-ip>:<port>?v=1&fp=<sha256>&token=<256-bit-random>&expires=<unix-ms>`

The displayed invitation expires in five minutes. Generating another invalidates the previous one. `POST /v1/pair` sends JSON `name` and `token` over the pinned TLS connection. A valid token is consumed before user approval, even if the user rejects it. On approval the receiver issues a new 256-bit random bearer credential and stores authorization keyed by its SHA-256; the sender stores the credential in its OS vault. Inbound authorization names and hashes appear in local settings for revocation. A credential authenticates requests to this receiver, not a device name advertised by mDNS. Each direction is paired independently. Revoke-all closes receiving first and invalidates stored authorizations.

The invitation token is itself sensitive: anyone with the private invitation can ask to pair before it expires. The receiver must approve the expected device; names are user-provided and not a trustworthy identity proof. Lost invitations can be invalidated by generating another or disabling receiving. Pairing credentials must not appear in logs or SQLite transfer history.

## Transfer lifecycle

1. `POST /v1/offers`, authenticated with `Authorization: Bearer ...`, sends `{version,id,sender,files:[{path,size,sha256}]}`. IDs are unpredictable random strings. Paths are portable `/`-separated relative paths. Metadata is capped at 4 MiB and 10,000 entries; total size is capped at 1 PiB to avoid signed-integer overflow.
2. A new offer requires explicit user approval (60-second timeout). Only after approval does the receiver create a per-batch folder. Existing identical offers from the same credential resume; another owner or changed manifest gets HTTP 409.
3. The response contains `offsets`, `done` and `state`. `GET /v1/transfers/<id>` returns the same status to its authenticated owner.
4. `PUT /v1/transfers/<id>/files/<index>` carries a bounded binary chunk with exact `Content-Length` and `x-offset`. The receiver requires its committed offset, rejects duplicates/out-of-order chunks, and serializes uploads per transfer. A batch has one active sender; client connections and accepted request concurrency are bounded.
5. The receiver truncates uncommitted tail bytes, seeks to the durable offset, streams into `parts/<index>.part`, flushes and closes, then saves the offset in SQLite (`WAL`, `synchronous=FULL`). A zero-byte upload completes an empty file or restarts finalization at EOF.
6. At declared EOF it computes SHA-256 from disk. A mismatch resets that file's offset to zero and does not publish it. A match permits rename into the approved batch's `files/` subtree. Existing targets are never intentionally overwritten. Crash recovery recognizes a matching target after rename before the checkpoint commit.
7. `state=complete` means every file was verified and finalized. Only then does the sender record success. History contains counts, sizes, timestamps, device label and receiver folder; it contains no credentials.
8. `DELETE /v1/transfers/<id>` cancels future uploads for that batch. Cancelling locally tries this endpoint but cannot promise delivery while offline. Partial data is retained for inspection, not silently deleted.

HTTP statuses: 400 malformed metadata/request; 401 unpaired; 403 expired/rejected invitation or consent; 404 unknown resource/owner; 409 conflicting state/offset; 422 hash mismatch; 429 pending consent; 503 request capacity; 507 filesystem write failure. Errors avoid returning arbitrary file contents or credential values.

## Path and integrity defenses

Reject absolute paths, backslashes, `.`/`..`, empty components, NUL/control characters, drive prefixes/NTFS alternate streams, Windows reserved device names, trailing dot/space aliases and portable invalid characters. Reject case-insensitive duplicates and file/directory overlaps. Limit path/component lengths. Validate directory ancestry and reject symlinks before publication. Exclude symlinks during source-folder collection.

This is application-level protection, not an OS sandbox against an attacker who can concurrently replace directories under the destination. Portable Dart APIs lack descriptor-relative `openat(O_NOFOLLOW)`/Windows handle equivalent. Use a receiver directory owned by your account; release hardening should add native race-resistant operations. There is no whole-file RAM buffering in application code; SAF providers may have their own implementation limits and need device testing.

## Resource and lifecycle limits

One upload at a time per batch, max 1 MiB per upload, max four active authenticated/parsing requests at the receiver, short metadata/body idle timeouts. Four requests are not a complete network-denial-of-service defense: TLS handshake/socket-level rate limiting and per-device disk quotas remain release-hardening work. Final SHA-256 can take time for large files and is performed from a stream; no background-service availability is implied on mobile. Saved processes never survive environment snapshots.

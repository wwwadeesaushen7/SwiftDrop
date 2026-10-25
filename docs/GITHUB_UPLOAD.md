# Push files to your GitHub repository

SwiftDrop 0.2 adds **Push to GitHub**, available from Home and the navigation menu on Android and desktop. This optional feature needs internet and a GitHub account. Nearby device transfers still work offline without an account.

## First upload

1. On GitHub, create a repository or choose an existing one you can write to. For a new repository, select **Add a README** so its branch exists. Check whether it is public or private.
2. Open [GitHub’s fine-grained personal access token page](https://github.com/settings/personal-access-tokens/new). Select the correct resource owner, an expiry, **Only select repositories**, and your destination repository. Under Repository permissions enable **Contents: Read and write**. An organization may require approval. Workflow file changes can require additional Workflow permission.
3. Copy the generated token. Keep it private; do not send it in chat or commit it to a repository.
4. Open **SwiftDrop → Push files to GitHub** (or **Menu → Push to GitHub**). Enter `owner/repository` or its `https://github.com/owner/repository` URL, the **existing branch** (often `main`), an optional destination folder, and the token.
5. Choose **Add files**, or **Add folder** on desktop. This uses the same selection as **Send files**. Desktop drag-and-drop works here too. Folder relative paths are preserved. Clear any files you do not want to upload.
6. Choose **Review upload**. SwiftDrop checks repository visibility and shows every destination path as **Add** or **Replace**. Public repository files can be downloaded by anyone. Check file contents before publishing.
7. If replacing files, enable **Replace existing files**. Enter a commit message and choose **Commit … files to GitHub**. Keep the app foregrounded while uploading.
8. Wait for **Files committed successfully**, then use **View commit on GitHub** or **Copy link** to see the result.

Use **Remember token** only if you want it stored in your device’s OS secure storage. The default keeps it only in app memory. Tokens never go into SQLite, transfer history, logs, QR invitations or local-device sharing requests. Unchecking Remember removes the saved token; **Forget token on this device** also clears the active session token. Revoke a token on GitHub to disable it everywhere.

## Limits and failure behavior

- Any readable file type is supported within GitHub’s regular repository limits: **100 MiB per file**, **200 files per batch** in SwiftDrop. The 200-file cap keeps review and API usage bounded.
- **Git LFS uploads and GitHub Release assets are not implemented.** For larger files, use Git with Git LFS or another suitable upload tool. SwiftDrop’s own universal debug APK exceeds this limit; its repository download is stored using Git LFS separately.
- Existing initialized github.com repositories and existing branches are supported. Repository creation, branch creation, GitHub Enterprise servers and OAuth login are not implemented.
- Source files must remain available and unchanged from review through upload. Android system-picker streams may be cached to app storage, as for nearby sends. Folder selection is desktop-only. Symlinks, submodules, `.git` metadata, unsafe relative paths, duplicate names and file/folder conflicts are rejected. Select project source files without their `.git` directory.
- Files stream one at a time through HTTPS with normal certificate validation and bounded Base64 encoding. Git blob SHA-1 IDs are computed while streaming and checked against GitHub’s responses. SHA-1 here is Git’s object format; nearby transfers continue to use SHA-256.
- Review only reads GitHub. Upload stages blobs and one tree/commit, preserving unselected files, then updates the branch once with `force: false`. A changed or protected branch is rejected; SwiftDrop never force-pushes.
- **Cancel** is available until the final branch update starts. No partial batch is published before that update. GitHub may retain unattached objects from cancelled uploads; cancellation does not erase data already sent to GitHub.
- Interrupted GitHub uploads restart from the beginning; nearby transfer checkpoints do not apply. If the final update response is lost, SwiftDrop shows a commit link and asks you to check the branch before retrying. An unattached commit link alone does not prove the branch was updated.
- GitHub rate limits, organization restrictions, required pull requests, protected branches and token expiry still apply. Choose an existing branch your token is allowed to update.
- A commit is persistent repository history. Replacing or deleting a file later does not remove its earlier contents from history. Review what you upload, especially to public repositories.

## Validation and manual check

Automated tests use actual HTTP sockets, file streams and a local GitHub API fixture. They verify binary/Unicode/empty files, replacements and executable modes, path and size limits, changed sources/branches, integrity rejection, cancelled batches, safe redirects, protected-branch errors and token persistence choices. Mobile and desktop widget tests open this screen.

**Live account uploads have not been verified here:** the managed cloud network blocks `api.github.com`. Android hardware and Windows runtime checks also remain unrun. Source tests and APK compilation do not establish those platform results.

On each target platform, use a disposable repository with a README:

- [ ] Token limited to that repository; upload a small text file, binary file, Unicode filename and empty file. Download and compare exact bytes/hashes.
- [ ] Confirm all files appear in one commit and an unrelated README is preserved.
- [ ] Replace a file only after checking the explicit replacement box.
- [ ] Choose a nested destination folder and an existing branch containing `/`.
- [ ] Reject expired/read-only/wrong-repository tokens without exposing token text.
- [ ] Reject a file above 100 MiB before any API call.
- [ ] Change the branch after review and confirm no force update occurs.
- [ ] Cancel and disconnect during upload, inspect the branch, then review/retry.
- [ ] Test branch protection and a connection loss during final publication; check the recovery link and branch before retrying.
- [ ] Remember/restart, then forget/restart, confirming OS vault behavior on the actual device.

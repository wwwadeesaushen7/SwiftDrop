import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/controller.dart';

class GitHubPullPanel extends StatelessWidget {
  final AppController app;
  final void Function(String path, bool refresh) browse;
  const GitHubPullPanel({super.key, required this.app, required this.browse});
  String size(int bytes) => bytes < 1024
      ? '$bytes B'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
  @override
  Widget build(BuildContext context) {
    final c = app.github;
    final listing = c.listing;
    final saved = c.pullResult;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pull files from GitHub',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Browse a folder, select files, then download them. Public repositories work without a token. Private repositories need Contents: Read access. Git LFS files download as their original contents.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: c.busy ? null : () => browse(c.folder, true),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Browse files'),
                ),
                if (listing != null) ...[
                  TextButton(
                    onPressed: c.busy ? null : () => browse('', false),
                    child: const Text('Repository root'),
                  ),
                  if (listing.target.folder.isNotEmpty)
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => browse(
                              listing.target.folder
                                  .split('/')
                                  .take(
                                    listing.target.folder.split('/').length - 1,
                                  )
                                  .join('/'),
                              false,
                            ),
                      child: const Text('Up one folder'),
                    ),
                ],
              ],
            ),
            if (listing != null) ...[
              const SizedBox(height: 12),
              Text(
                '${listing.target.folder.isEmpty ? '/' : listing.target.folder} · commit ${listing.commit.substring(0, 8)}',
              ),
              const Text(
                'Folder navigation keeps this commit. Browse files refreshes to the latest branch. Symlinks, submodules and names unsafe on Windows are omitted. Select files within one folder per batch.',
              ),
              if (listing.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No supported files or folders here.'),
                ),
              for (final entry in listing.entries)
                if (entry.isDirectory)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(entry.name, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: c.busy ? null : () => browse(entry.path, false),
                  )
                else
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${size(entry.size)} in Git; LFS contents may be larger',
                    ),
                    value: c.selectedRemote.contains(entry.path),
                    onChanged: c.busy
                        ? null
                        : (v) => c.selectRemote(entry.path, v ?? false),
                  ),
              const SizedBox(height: 12),
              SelectableText('Save under: ${c.downloadDestination}'),
              if (!Platform.isAndroid && !Platform.isIOS)
                TextButton.icon(
                  onPressed: c.busy || app.busy
                      ? null
                      : () => app.guard(app.chooseGitHubDestination),
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('Choose download folder'),
                )
              else
                const Text(
                  'Files are saved in app storage. After download, export them to Downloads.',
                ),
              const SizedBox(height: 8),
              const Text(
                'A new folder is created for each pull. Existing local files are preserved. This downloads files; it does not merge a local Git working copy.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: c.busy || c.selectedRemote.isEmpty
                    ? null
                    : c.pullSelected,
                icon: const Icon(Icons.download),
                label: Text('Pull ${c.selectedRemote.length} selected files'),
              ),
            ],
            if (saved != null) ...[
              const SizedBox(height: 16),
              Text(
                '${saved.files} files downloaded and verified · ${size(saved.bytes)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(saved.path),
              if (Platform.isAndroid)
                OutlinedButton.icon(
                  onPressed: app.busy
                      ? null
                      : () => app.guard(() async {
                          final count =
                              await const MethodChannel('app.swiftdrop/files')
                                  .invokeMethod<int>('exportBatch', {
                                    'path': saved.path,
                                  });
                          app.setError(
                            'Exported $count files to Downloads/SwiftDrop.',
                          );
                        }),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Export to Downloads'),
                )
              else if (!Platform.isIOS)
                OutlinedButton.icon(
                  onPressed: app.busy
                      ? null
                      : () => app.guard(() async {
                          if (!await launchUrl(Uri.directory(saved.path))) {
                            throw StateError('Could not open saved folder');
                          }
                        }),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open downloaded files'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

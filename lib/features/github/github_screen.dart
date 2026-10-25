import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/controller.dart';
import 'github_controller.dart';

class GitHubScreen extends StatefulWidget {
  final AppController app;
  const GitHubScreen({super.key, required this.app});
  @override
  State<GitHubScreen> createState() => _GitHubScreenState();
}

class _GitHubScreenState extends State<GitHubScreen> {
  GitHubController get c => widget.app.github;
  late final repository = TextEditingController(text: c.repository);
  late final branch = TextEditingController(text: c.branch);
  late final folder = TextEditingController(text: c.folder);
  late final token = TextEditingController(text: c.token);
  final message = TextEditingController(text: 'Upload files with SwiftDrop');
  bool replace = false;
  @override
  void dispose() {
    repository.dispose();
    branch.dispose();
    folder.dispose();
    token.dispose();
    message.dispose();
    super.dispose();
  }

  void invalidate() {
    replace = false;
    c.invalidate();
  }

  Future<void> openUrl(String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open browser. Copy the link instead.'),
      ),
    );
  }

  Widget field(
    TextEditingController controller,
    String label,
    void Function(String) update, {
    String? hint,
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      enabled: !c.busy,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      decoration: InputDecoration(labelText: label, hintText: hint),
      onChanged: (value) {
        update(value);
        invalidate();
      },
    ),
  );

  Widget link(String url, String label) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton.icon(
        onPressed: () => openUrl(url),
        icon: const Icon(Icons.open_in_new),
        label: Text(label),
      ),
      TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Link copied')));
          }
        },
        icon: const Icon(Icons.copy),
        label: const Text('Copy link'),
      ),
    ],
  );

  String size(int bytes) => bytes < 1024
      ? '$bytes B'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final plan = c.plan;
      final progress = c.progress;
      final disabled = c.busy || widget.app.busy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Push to GitHub',
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload selected files to a repository you can write to. Internet and a GitHub account are required.',
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connect your repository',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  field(
                    repository,
                    'Repository',
                    (v) => c.repository = v,
                    hint: 'owner/repository or https://github.com/owner/repository',
                  ),
                  field(
                    branch,
                    'Existing branch',
                    (v) => c.branch = v,
                    hint: 'main',
                  ),
                  field(
                    folder,
                    'Destination folder (optional)',
                    (v) => c.folder = v,
                    hint: 'uploads/photos',
                  ),
                  field(
                    token,
                    'Personal access token',
                    (v) => c.token = v,
                    secret: true,
                  ),
                  const Text(
                    'Use a fine-grained token limited to this repository, with Contents: Read and write. Your token is sent only to api.github.com over HTTPS.',
                  ),
                  TextButton.icon(
                    onPressed: () => openUrl(
                      'https://github.com/settings/personal-access-tokens/new',
                    ),
                    icon: const Icon(Icons.key),
                    label: const Text('Create a GitHub token'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Remember token in this device’s secure storage',
                    ),
                    value: c.rememberToken,
                    onChanged: c.busy
                        ? null
                        : (value) => c.setRememberToken(value ?? false),
                  ),
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () async {
                            await c.forgetToken();
                            if (mounted) token.text = c.token;
                          },
                    child: const Text('Forget token on this device'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose files',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Uses the same selection as Send files. Any file type, up to 100 MiB per file and 200 files per commit. Larger files require Git LFS outside SwiftDrop.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: disabled
                            ? null
                            : () async {
                                invalidate();
                                await widget.app.guard(widget.app.pickFiles);
                              },
                        icon: const Icon(Icons.add),
                        label: const Text('Add files'),
                      ),
                      if (!Platform.isAndroid && !Platform.isIOS)
                        OutlinedButton.icon(
                          onPressed: disabled
                              ? null
                              : () async {
                                  invalidate();
                                  await widget.app.guard(widget.app.pickFolder);
                                },
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Add folder'),
                        ),
                      TextButton(
                        onPressed: disabled
                            ? null
                            : () {
                                invalidate();
                                widget.app.clearSelection();
                              },
                        child: const Text('Clear selection'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${widget.app.selection.length} files · ${size(widget.app.selectionBytes)}',
                  ),
                  for (final source in widget.app.selection.take(20))
                    Text(source.relativePath, overflow: TextOverflow.ellipsis),
                  if (widget.app.selection.length > 20)
                    const Text('Full destination list appears after review.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: disabled || widget.app.selection.isEmpty
                        ? null
                        : () {
                            replace = false;
                            c.preview(widget.app.selection);
                          },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Review upload'),
                  ),
                ],
              ),
            ),
          ),
          if (plan != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${plan.target.name} → ${plan.target.branch}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      plan.isPrivate
                          ? 'Private repository. People with repository access can see these files.'
                          : 'Public repository: anyone can download these files.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Review file contents before committing. Repository history retains previous versions; do not upload passwords or private keys.',
                    ),
                    const SizedBox(height: 12),
                    for (final file in plan.files)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '${file.replaces ? 'Replace' : 'Add'} · ${file.path} · ${size(file.stat.size)}',
                        ),
                      ),
                    if (plan.replacements > 0)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: replace,
                        onChanged: c.busy
                            ? null
                            : (v) => setState(() => replace = v ?? false),
                        title: Text(
                          'Replace ${plan.replacements} existing file(s) in this commit',
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: message,
                      enabled: !c.busy,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Commit message',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: c.busy || (plan.replacements > 0 && !replace)
                          ? null
                          : () => c.upload(message.text),
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        'Commit ${plan.files.length} files to GitHub',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (c.busy && progress != null) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: progress.total > 0 && progress.state == 'Uploading'
                  ? (progress.bytes / progress.total).clamp(0, 1)
                  : null,
            ),
            const SizedBox(height: 8),
            Text('${progress.state} ${progress.file}'),
            if (progress.total > 0)
              Text('${size(progress.bytes)} / ${size(progress.total)} sent'),
            TextButton(
              onPressed: progress.canCancel ? c.cancel : null,
              child: Text(progress.canCancel ? 'Cancel' : 'Finishing commit…'),
            ),
            const Text(
              'Keep mobile uploads in the foreground. Interrupted uploads must be restarted; the branch updates only after the batch is ready.',
            ),
          ],
          if (c.error != null) ...[
            const SizedBox(height: 16),
            Text(
              c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (c.recoveryUrl != null)
            link(c.recoveryUrl!, 'Check commit on GitHub'),
          if (c.commitUrl != null) ...[
            const SizedBox(height: 16),
            const Text(
              'Files committed successfully.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            link(c.commitUrl!, 'View commit on GitHub'),
          ],
        ],
      );
    },
  );
}

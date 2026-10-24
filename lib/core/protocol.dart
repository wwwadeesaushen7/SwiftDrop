import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

const protocolVersion = 1;
const chunkSize = 1024 * 1024;
const maxFiles = 10000;
const maxMetadataBytes = 4 * 1024 * 1024;

String randomToken([int bytes = 32]) => base64Url
    .encode(List<int>.generate(bytes, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');

bool constantTimeEquals(String a, String b) {
  final aa = utf8.encode(a), bb = utf8.encode(b);
  var difference = aa.length ^ bb.length;
  for (var i = 0; i < max(aa.length, bb.length); i++) {
    difference |= (i < aa.length ? aa[i] : 0) ^ (i < bb.length ? bb[i] : 0);
  }
  return difference == 0;
}

/// Portable subset: reject Windows aliases and alternate data streams even on
/// Unix receivers. Never interpret peer paths with the host's path semantics.
String safeRelativePath(String value) {
  if (value.isEmpty ||
      value.length > 1024 ||
      value.startsWith('/') ||
      value.contains('\\') ||
      value.contains(RegExp(r'[\x00-\x1f\x7f:<>"|?*]'))) {
    throw const FormatException('Unsafe file path');
  }
  for (final part in value.split('/')) {
    if (part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.endsWith('.') ||
        part.endsWith(' ') ||
        utf8.encode(part).length > 240 ||
        RegExp(
          r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
          caseSensitive: false,
        ).hasMatch(part)) {
      throw const FormatException('Unsafe file path');
    }
  }
  return value;
}

Future<String> hashFile(File file, {bool Function()? cancelled}) async =>
    (await sha256
            .bind(
              file.openRead().map((block) {
                if (cancelled?.call() ?? false) {
                  throw StateError('Hashing cancelled');
                }
                return block;
              }),
            )
            .first)
        .toString();

Future<Map<String, dynamic>> readJson(
  Stream<List<int>> stream, {
  int limit = maxMetadataBytes,
}) async {
  final bytes = <int>[];
  await for (final block in stream) {
    if (bytes.length + block.length > limit) {
      throw const FormatException('Metadata too large');
    }
    bytes.addAll(block);
  }
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return value;
}

class FileEntry {
  final String path;
  final int size;
  final String digest;
  const FileEntry(this.path, this.size, this.digest);
  Map<String, dynamic> toJson() => {
    'path': path,
    'size': size,
    'sha256': digest,
  };
  factory FileEntry.fromJson(Map<String, dynamic> json) {
    final path = safeRelativePath(json['path'] as String);
    final size = json['size'] as int;
    final digest = json['sha256'] as String;
    if (size < 0 ||
        size > 0x7fffffffffffffff ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid file metadata');
    }
    return FileEntry(path, size, digest);
  }
}

class Manifest {
  final String id;
  final String sender;
  final List<FileEntry> files;
  Manifest(this.id, this.sender, this.files) {
    if (!RegExp(r'^[A-Za-z0-9_-]{20,64}$').hasMatch(id) ||
        sender.isEmpty ||
        sender.length > 100 ||
        files.isEmpty ||
        files.length > maxFiles) {
      throw const FormatException('Invalid transfer manifest');
    }
    final paths = <String>{};
    var total = 0;
    for (final f in files) {
      safeRelativePath(f.path);
      // Bound totals below signed 64-bit overflow while supporting >4 GB files.
      if (f.size < 0 ||
          f.size > (1 << 50) - total ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(f.digest)) {
        throw const FormatException('Invalid size/hash or batch exceeds 1 PiB');
      }
      total += f.size;
      if (!paths.add(f.path.toLowerCase())) {
        throw const FormatException('Duplicate paths');
      }
    }
    for (final path in paths) {
      final parts = path.split('/');
      for (var length = 1; length < parts.length; length++) {
        if (paths.contains(parts.take(length).join('/'))) {
          throw const FormatException('File overlaps a directory');
        }
      }
    }
  }
  int get total => files.fold(0, (sum, f) => sum + f.size);
  Map<String, dynamic> toJson() => {
    'version': protocolVersion,
    'id': id,
    'sender': sender,
    'files': files.map((f) => f.toJson()).toList(),
  };
  factory Manifest.fromJson(Map<String, dynamic> json) {
    if (json['version'] != protocolVersion) {
      throw const FormatException('Unsupported protocol');
    }
    return Manifest(
      json['id'] as String,
      json['sender'] as String,
      (json['files'] as List)
          .map((f) => FileEntry.fromJson(Map<String, dynamic>.from(f as Map)))
          .toList(),
    );
  }
}

bool isPrivateAddress(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final b = address.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      b[0] == 127 ||
      (b[0] == 169 && b[1] == 254);
}

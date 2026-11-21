import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';

// CI har build par --dart-define=BUILD_NUMBER=<run number> deta hai
const buildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);
const _base = 'https://github.com/rohitrot738/walkie-talkie-/releases/download/latest';

bool _busy = false;
DateTime? _lastCheck;

/// GitHub release se naya build dhoondta hai; mile to download + install karwata hai.
Future<void> checkForUpdate(BuildContext context, {bool silent = true}) async {
  if (_busy) return;
  final last = _lastCheck;
  if (silent && last != null && DateTime.now().difference(last) < const Duration(minutes: 5)) return;
  _busy = true;
  try {
    final info = await _fetchInfo();
    _lastCheck = DateTime.now();
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (info == null) {
      if (!silent) messenger.showSnackBar(const SnackBar(content: Text('Update check nahi ho paya')));
      return;
    }
    if ((info['build'] as int) <= buildNumber) {
      if (!silent) messenger.showSnackBar(SnackBar(content: Text('App up to date (build $buildNumber)')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Naya update available'),
        content: Text('Build ${info['build']}\n${info['notes'] ?? ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Baad mein')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
        ],
      ),
    );
    if (ok == true && context.mounted) await _install(context, info);
  } finally {
    _busy = false;
  }
}

Future<Map<String, dynamic>?> _fetchInfo() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse('$_base/version.json'));
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<void> _install(BuildContext context, Map<String, dynamic> info) async {
  final progress = ValueNotifier<String>('Download shuru ho raha hai...');
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Updating'),
      content: ValueListenableBuilder<String>(valueListenable: progress, builder: (_, v, __) => Text(v)),
    ),
  );
  String? error;
  try {
    final events = OtaUpdate().execute(
      '$_base/walkie-talkie.apk',
      destinationFilename: 'walkie-talkie.apk',
      sha256checksum: info['sha256'] as String?,
    );
    await for (final e in events) {
      switch (e.status) {
        case OtaStatus.DOWNLOADING:
          progress.value = 'Downloading ${e.value}%';
        case OtaStatus.INSTALLING:
          progress.value = 'Install prompt mein "Install" dabayein';
        case OtaStatus.INSTALLATION_DONE:
          break;
        default:
          error = '${e.status.name} ${e.value ?? ''}';
      }
    }
  } catch (e) {
    error = '$e';
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update fail: $error')));
  }
}

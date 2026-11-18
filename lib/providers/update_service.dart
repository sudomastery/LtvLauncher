/*
 * Checks the project's GitHub releases and installs a newer version over the running app.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:convert';
import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// A published release that has an APK for this device.
class ReleaseInfo {
  final String tag;
  final String version;
  final String notes;
  final String apkName;
  final Uri apkUrl;
  final Uri? checksumUrl;

  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.apkName,
    required this.apkUrl,
    this.checksumUrl,
  });
}

enum UpdateStatus { idle, checking, upToDate, available, downloading, installing, installed, error }

typedef HttpGetText = Future<String> Function(Uri uri);
typedef HttpDownload = Future<void> Function(Uri uri, File target, void Function(double progress) onProgress);

class UpdateService extends ChangeNotifier {
  /// Where releases are looked up. Only this repository is ever contacted for updates.
  static const releasesUrl = 'https://api.github.com/repos/sudomastery/LtvLauncher/releases/latest';

  final FLauncherChannel _channel;
  final SettingsService? _settings;
  final HttpGetText _get;
  final HttpDownload _download;
  final Future<String> Function() _currentVersion;

  final DateTime Function() _now;
  bool _dismissedThisSession = false;
  UpdateStatus _status = UpdateStatus.idle;
  String _installedVersion = '';
  ReleaseInfo? _latest;
  double _progress = 0;
  String? _error;

  /// How long to wait between automatic checks.
  static const autoCheckEvery = Duration(hours: 24);

  UpdateService(
    this._channel, {
    SettingsService? settings,
    DateTime Function()? now,
    HttpGetText? get,
    HttpDownload? download,
    Future<String> Function()? currentVersion,
  })  : _settings = settings,
        _now = now ?? DateTime.now,
        _get = get ?? _defaultGet,
        _download = download ?? _defaultDownload,
        _currentVersion = currentVersion ?? _packageVersion;

  /// The settings the banner and automatic checks follow (null in unit tests that do not need them).
  SettingsService? get settings => _settings;

  UpdateStatus get status => _status;

  /// True while the update banner should be on screen: an update was found, the user has not ignored
  /// this version, switched the banner off, or closed it for now.
  bool get bannerVisible {
    final release = _latest;
    if (release == null || _dismissedThisSession) return false;
    final settings = _settings;
    if (settings != null) {
      if (!settings.updateChecksEnabled) return false;
      if (settings.ignoredUpdateVersion == release.version) return false;
    }
    return _status == UpdateStatus.available ||
        _status == UpdateStatus.downloading ||
        _status == UpdateStatus.installing ||
        _status == UpdateStatus.installed ||
        _status == UpdateStatus.error;
  }

  /// Looks for an update by itself, at most once a day, and only when the user has not switched updates off.
  /// Errors stay silent: a failed automatic check shows nothing.
  Future<void> autoCheck() async {
    final settings = _settings;
    if (settings == null || !settings.updateChecksEnabled) return;
    final last = DateTime.fromMillisecondsSinceEpoch(settings.lastUpdateCheckMillis);
    if (settings.lastUpdateCheckMillis != 0 && _now().difference(last) < autoCheckEvery) return;
    final reachedGitHub = await check(quiet: true);
    // A check that could not reach GitHub is not counted, so it is tried again soon.
    if (reachedGitHub) {
      await settings.setLastUpdateCheckMillis(_now().millisecondsSinceEpoch);
    }
  }

  /// "Ignore": do not announce this version again (a newer one will be).
  Future<void> ignoreThisVersion() async {
    final release = _latest;
    if (release == null) return;
    await _settings?.setIgnoredUpdateVersion(release.version);
    notifyListeners();
  }

  /// "Never show updates": no banner and no automatic checks. Settings, Updates still works by hand.
  Future<void> neverShowUpdates() async {
    await _settings?.setUpdateChecksEnabled(false);
    notifyListeners();
  }

  /// Hides the banner until the launcher is started again (Back button).
  void dismissForNow() {
    _dismissedThisSession = true;
    notifyListeners();
  }
  String get installedVersion => _installedVersion;
  ReleaseInfo? get latest => _latest;
  double get progress => _progress;
  String? get error => _error;

  void _set(UpdateStatus status, {String? error}) {
    _status = status;
    _error = error;
    notifyListeners();
  }

  /// Looks for a newer release. Ends in [UpdateStatus.available], [UpdateStatus.upToDate] or [UpdateStatus.error].
  /// Returns true when GitHub could be reached (whether or not an update exists).
  Future<bool> check({bool quiet = false}) async {
    _set(UpdateStatus.checking);
    try {
      _installedVersion = await _currentVersion();
      final body = await _get(Uri.parse(releasesUrl));
      final release = jsonDecode(body) as Map<String, dynamic>;
      final tag = (release['tag_name'] as String?) ?? '';
      final version = versionOfTag(tag);
      if (version.isEmpty || !isNewer(version, _installedVersion)) {
        _latest = null;
        _set(UpdateStatus.upToDate);
        return true;
      }
      final abis = await _channel.getSupportedAbis();
      final asset = pickApkAsset((release['assets'] as List?) ?? const [], abis);
      if (asset == null) {
        _set(UpdateStatus.error, error: 'Release $tag has no APK for this TV.');
        return true;
      }
      final assets = (release['assets'] as List).cast<Map<String, dynamic>>();
      final checksum = assets.firstWhere(
        (a) => a['name'] == '${asset['name']}.sha256',
        orElse: () => const {},
      );
      _latest = ReleaseInfo(
        tag: tag,
        version: version,
        notes: ((release['body'] as String?) ?? '').trim(),
        apkName: asset['name'] as String,
        apkUrl: Uri.parse(asset['browser_download_url'] as String),
        checksumUrl: checksum['browser_download_url'] == null ? null : Uri.parse(checksum['browser_download_url'] as String),
      );
      _set(UpdateStatus.available);
      return true;
    } catch (e) {
      // An automatic check that fails (no network, rate limit) is silent.
      _set(quiet ? UpdateStatus.idle : UpdateStatus.error, error: quiet ? null : _readable(e));
      return false;
    }
  }

  /// Downloads the update found by [check], verifies its checksum and installs it over this app.
  Future<void> downloadAndInstall() async {
    final release = _latest;
    if (release == null) return;
    if (release.checksumUrl == null) {
      _set(UpdateStatus.error, error: 'This release has no checksum file, so it will not be installed.');
      return;
    }
    try {
      _progress = 0;
      _set(UpdateStatus.downloading);
      final checksum = parseChecksum(await _get(release.checksumUrl!));
      if (checksum == null) {
        _set(UpdateStatus.error, error: 'The checksum file could not be read.');
        return;
      }
      final folder = await _channel.getUpdateDirectory();
      if (folder.isEmpty) {
        _set(UpdateStatus.error, error: 'No place to store the update.');
        return;
      }
      await Directory(folder).create(recursive: true);
      final target = File('$folder/${release.apkName}');
      await _download(release.apkUrl, target, (p) {
        _progress = p;
        notifyListeners();
      });

      _set(UpdateStatus.installing);
      final result = await _channel.installUpdate(target.path, checksum);
      if (result['ok'] == true) {
        _set(UpdateStatus.installed);
      } else {
        final message = (result['message'] as String?)?.trim();
        _set(UpdateStatus.error, error: (message == null || message.isEmpty) ? 'The update was not installed.' : message);
      }
    } catch (e) {
      _set(UpdateStatus.error, error: _readable(e));
    }
  }

  // ---------- pure helpers (unit tested) ----------

  /// "v2026.11.18" -> "2026.11.18".
  static String versionOfTag(String tag) => tag.trim().replaceFirst(RegExp(r'^[vV]'), '');

  /// True when [candidate] is a higher version than [current]. Compares number by number, so
  /// 2026.11.18.2 > 2026.11.18 and 2026.12.1 > 2026.11.30.
  static bool isNewer(String candidate, String current) {
    List<int> parts(String v) => v
        .split(RegExp(r'[.+\-]'))
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final a = parts(versionOfTag(candidate));
    final b = parts(versionOfTag(current));
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Picks the APK for the TV's CPU: the first of [abis] that has a matching file, then the universal one.
  static Map<String, dynamic>? pickApkAsset(List<dynamic> assets, List<String> abis) {
    final apks = assets.cast<Map<String, dynamic>>().where((a) => (a['name'] as String? ?? '').endsWith('.apk')).toList();
    for (final abi in abis) {
      for (final asset in apks) {
        if ((asset['name'] as String).endsWith('-$abi.apk')) return asset;
      }
    }
    for (final asset in apks) {
      if ((asset['name'] as String).contains('universal')) return asset;
    }
    return null;
  }

  /// Reads the SHA-256 from a "<hash>  <file name>" line (or just the hash).
  static String? parseChecksum(String text) {
    final match = RegExp(r'\b[0-9a-fA-F]{64}\b').firstMatch(text);
    return match?.group(0)?.toLowerCase();
  }

  static String _readable(Object e) {
    if (e is SocketException) return 'No connection to GitHub (${e.message}).';
    if (e is HttpException) return e.message;
    return e.toString();
  }

  // ---------- real network and package access ----------

  static Future<String> _packageVersion() async => (await PackageInfo.fromPlatform()).version;

  static Future<String> _defaultGet(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'LTvLauncher-Enhanced');
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode == 404) {
        throw const HttpException('No release has been published yet.');
      }
      if (response.statusCode != 200) {
        throw HttpException('GitHub answered ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  static Future<void> _defaultDownload(Uri uri, File target, void Function(double) onProgress) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'LTvLauncher-Enhanced');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('The download failed (${response.statusCode}).');
      }
      final total = response.contentLength;
      var received = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }
}

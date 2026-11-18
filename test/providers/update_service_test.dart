/*
 * Tests for checking for and installing updates.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:convert';
import 'dart:io';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

const _hash = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

String _release({String tag = 'v2026.11.18', bool checksum = true, String body = 'Fixes and new things'}) => jsonEncode({
      'tag_name': tag,
      'body': body,
      'assets': [
        {'name': 'LTvLauncher-Enhanced-arm64-v8a.apk', 'browser_download_url': 'https://example.test/arm64.apk'},
        {'name': 'LTvLauncher-Enhanced-armeabi-v7a.apk', 'browser_download_url': 'https://example.test/v7a.apk'},
        {'name': 'LTvLauncher-Enhanced-universal.apk', 'browser_download_url': 'https://example.test/universal.apk'},
        if (checksum) {'name': 'LTvLauncher-Enhanced-armeabi-v7a.apk.sha256', 'browser_download_url': 'https://example.test/v7a.sha256'},
        if (checksum) {'name': 'LTvLauncher-Enhanced-arm64-v8a.apk.sha256', 'browser_download_url': 'https://example.test/arm64.sha256'},
      ],
    });

void main() {
  group('version helpers', () {
    test('compares versions number by number', () {
      expect(UpdateService.isNewer('v2026.11.18', '2026.10.27'), isTrue);
      expect(UpdateService.isNewer('2026.12.1', '2026.11.30'), isTrue);
      expect(UpdateService.isNewer('2026.11.18.2', '2026.11.18'), isTrue);
      expect(UpdateService.isNewer('2026.11.18', '2026.11.18'), isFalse);
      expect(UpdateService.isNewer('2026.10.27', '2026.11.18'), isFalse);
      expect(UpdateService.isNewer('2026.11.18', '2026.11.18+8114'), isFalse);
    });

    test('picks the APK for the TV CPU, falling back to the universal one', () {
      final assets = (jsonDecode(_release())['assets'] as List);
      expect(UpdateService.pickApkAsset(assets, ['armeabi-v7a', 'armeabi'])!['name'], 'LTvLauncher-Enhanced-armeabi-v7a.apk');
      expect(UpdateService.pickApkAsset(assets, ['arm64-v8a', 'armeabi-v7a'])!['name'], 'LTvLauncher-Enhanced-arm64-v8a.apk');
      expect(UpdateService.pickApkAsset(assets, ['x86_64'])!['name'], 'LTvLauncher-Enhanced-universal.apk');
      expect(UpdateService.pickApkAsset(const [], ['arm64-v8a']), isNull);
    });

    test('reads a SHA-256 from a checksum file', () {
      expect(UpdateService.parseChecksum('$_hash  LTvLauncher-Enhanced-armeabi-v7a.apk\n'), _hash);
      expect(UpdateService.parseChecksum(_hash.toUpperCase()), _hash);
      expect(UpdateService.parseChecksum('not a checksum'), isNull);
    });
  });

  group('checking and installing', () {
    late MockFLauncherChannel channel;
    late Directory temp;

    setUp(() async {
      channel = MockFLauncherChannel();
      when(channel.getSupportedAbis()).thenAnswer((_) async => ['armeabi-v7a', 'armeabi']);
      temp = await Directory.systemTemp.createTemp('update_test');
      when(channel.getUpdateDirectory()).thenAnswer((_) async => '${temp.path}/update');
    });

    tearDown(() async => temp.delete(recursive: true));

    UpdateService service({
      String release = '',
      String installed = '2026.10.27',
      List<Uri>? requests,
      SettingsService? settings,
      DateTime Function()? now,
      Future<void> Function(Uri, File, void Function(double))? download,
    }) {
      return UpdateService(
        channel,
        settings: settings,
        now: now,
        currentVersion: () async => installed,
        get: (uri) async {
          requests?.add(uri);
          if (uri.path.endsWith('.sha256')) return '$_hash  file.apk';
          return release.isEmpty ? _release() : release;
        },
        download: download ?? (uri, file, progress) async {
          await file.writeAsBytes([1, 2, 3]);
          progress(1);
        },
      );
    }

    test('finds a newer release and the right APK and checksum for this TV', () async {
      final update = service();
      await update.check();

      expect(update.status, UpdateStatus.available);
      expect(update.latest!.version, '2026.11.18');
      expect(update.latest!.apkName, 'LTvLauncher-Enhanced-armeabi-v7a.apk');
      expect(update.latest!.checksumUrl.toString(), 'https://example.test/v7a.sha256');
    });

    test('says up to date when the release is not newer', () async {
      final update = service(installed: '2026.11.18');
      await update.check();
      expect(update.status, UpdateStatus.upToDate);
      expect(update.latest, isNull);
    });

    test('downloads, then installs only with the published checksum', () async {
      when(channel.installUpdate(any, any)).thenAnswer((_) async => {'ok': true, 'message': 'Success'});
      final update = service();
      await update.check();

      await update.downloadAndInstall();

      expect(update.status, UpdateStatus.installed);
      verify(channel.installUpdate('${temp.path}/update/LTvLauncher-Enhanced-armeabi-v7a.apk', _hash)).called(1);
    });

    test('refuses to install a release that has no checksum file', () async {
      final update = service(release: _release(checksum: false));
      await update.check();

      await update.downloadAndInstall();

      expect(update.status, UpdateStatus.error);
      verifyNever(channel.installUpdate(any, any));
    });

    test('reports why an install failed', () async {
      when(channel.installUpdate(any, any)).thenAnswer((_) async => {'ok': false, 'message': 'The downloaded update does not match its checksum.'});
      final update = service();
      await update.check();
      await update.downloadAndInstall();

      expect(update.status, UpdateStatus.error);
      expect(update.error, contains('checksum'));
    });

    group('automatic checks and the banner', () {
      late SettingsService settings;
      var clock = DateTime(2026, 11, 18, 9);

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        settings = SettingsService(await SharedPreferences.getInstance());
        clock = DateTime(2026, 11, 18, 9);
      });

      test('shows the banner for a new version, then respects Ignore for that version only', () async {
        final update = service(settings: settings, now: () => clock);
        await update.autoCheck();
        expect(update.bannerVisible, isTrue);

        await update.ignoreThisVersion();
        expect(update.bannerVisible, isFalse);
        expect(settings.ignoredUpdateVersion, '2026.11.18');

        // A newer release is announced again.
        final newer = service(settings: settings, now: () => clock.add(const Duration(days: 2)), release: _release(tag: 'v2026.11.20'));
        await newer.autoCheck();
        expect(newer.bannerVisible, isTrue);
      });

      test('checks at most once a day', () async {
        final requests = <Uri>[];
        final update = service(settings: settings, now: () => clock, requests: requests);

        await update.autoCheck();
        await update.autoCheck();
        expect(requests.length, 1);

        clock = clock.add(const Duration(hours: 25));
        await update.autoCheck();
        expect(requests.length, 2);
      });

      test('Never show updates stops the banner and the automatic checks, but not manual checks', () async {
        final requests = <Uri>[];
        final update = service(settings: settings, now: () => clock, requests: requests);
        await update.autoCheck();
        expect(update.bannerVisible, isTrue);

        await update.neverShowUpdates();
        expect(settings.updateChecksEnabled, isFalse);
        expect(update.bannerVisible, isFalse);

        clock = clock.add(const Duration(days: 3));
        final before = requests.length;
        await update.autoCheck();
        expect(requests.length, before); // no automatic request any more

        await update.check(); // the manual check still works
        expect(update.status, UpdateStatus.available);
        expect(requests.length, before + 1);
      });

      test('Back hides the banner only until the next start', () async {
        final update = service(settings: settings, now: () => clock);
        await update.autoCheck();
        update.dismissForNow();
        expect(update.bannerVisible, isFalse);
        expect(settings.ignoredUpdateVersion, isNull);
      });

      test('a failed automatic check is silent and is tried again next time', () async {
        final failing = UpdateService(
          channel,
          settings: settings,
          now: () => clock,
          currentVersion: () async => '2026.10.27',
          get: (_) async => throw const SocketException('offline'),
        );

        await failing.autoCheck();

        expect(failing.status, UpdateStatus.idle);
        expect(failing.bannerVisible, isFalse);
        expect(settings.lastUpdateCheckMillis, 0);
      });
    });
  });
}

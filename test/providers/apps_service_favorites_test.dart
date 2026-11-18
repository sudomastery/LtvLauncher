/*
 * Tests for the default Favorites row (TizenTube, Plex, Prime Video, Netflix, Spotify, Twitch).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:typed_data';

import 'package:flauncher/database.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

Map<String, dynamic> _app(String packageName, String name) =>
    {'packageName': packageName, 'name': name, 'version': '1.0.0', 'sideloaded': false};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FLauncherDatabase database;
  late MockFLauncherChannel channel;

  setUp(() {
    // These tests are about the default favorites, so skip the first-run picker (see the onboarding tests below).
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    database = FLauncherDatabase.inMemory();
    channel = MockFLauncherChannel();
    when(channel.getApplicationIcon(any)).thenAnswer((_) async => Uint8List(0));
    when(channel.getApplicationBanner(any)).thenAnswer((_) async => Uint8List(0));
  });

  tearDown(() async {
    await database.close();
  });

  Future<AppsService> start(List<Map<String, dynamic>> installed) async {
    when(channel.getApplications()).thenAnswer((_) async => installed);
    final service = AppsService(channel, database);
    while (!service.initialized) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    // Seeding runs right after the default categories are created.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return service;
  }

  Category favorites(AppsService service) =>
      service.launcherSections.whereType<Category>().firstWhere((c) => c.name == 'Favorites');

  test('puts the installed default favorites first, in order, and skips apps that are not installed', () async {
    final service = await start([
      _app('com.spotify.tv.android', 'Spotify'),
      _app('com.example.other', 'Other'),
      _app('io.gh.reisxd.tizentube.cobalt', 'TizenTube'),
    ]);

    expect(service.launcherSections.first, isA<Category>());
    expect((service.launcherSections.first as Category).name, 'Favorites');

    final packages = favorites(service).applications.map((a) => a.packageName).toList();
    expect(packages, ['io.gh.reisxd.tizentube.cobalt', 'com.spotify.tv.android']);
    expect(packages, isNot(contains('com.example.other')));
  });

  test('shows no favorites when none of the default apps are installed', () async {
    final service = await start([_app('com.example.other', 'Other')]);

    expect(favorites(service).applications, isEmpty);
  });

  test('the Favorites row height is stored in the database, not just in memory', () async {
    final service = await start([_app('io.gh.reisxd.tizentube.cobalt', 'TizenTube')]);
    expect(favorites(service).rowHeight, 90);

    final stored = await database.getCategories();
    expect(stored.firstWhere((c) => c.name == 'Favorites').rowHeight, 90);
  });

  group('first-run onboarding', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a fresh install asks the user and starts with an empty Favorites row', () async {
      final service = await start([
        _app('io.gh.reisxd.tizentube.cobalt', 'TizenTube'),
        _app('com.spotify.tv.android', 'Spotify'),
        _app('com.example.other', 'Other'),
      ]);

      expect(service.onboardingActive, isTrue);
      expect(favorites(service).applications, isEmpty);
      // The well known apps are suggested, the rest can still be picked.
      expect(service.onboardingSuggestions.map((a) => a.packageName),
          ['io.gh.reisxd.tizentube.cobalt', 'com.spotify.tv.android']);
      expect(service.onboardingChoices.map((a) => a.packageName), contains('com.example.other'));
    });

    test('the TV system software is not offered as a choice', () async {
      final service = await start([
        _app('com.tcl.tv', 'TV'),
        _app('com.android.tv.settings', 'TV Settings'),
        _app('com.android.vending', 'Play Store'),
        _app('com.leanbitlab.ltvL.fork', 'LTvLauncher Enhanced'),
        _app('com.example.player', 'Player'),
      ]);

      final offered = service.onboardingChoices.map((a) => a.packageName).toList();
      expect(offered, containsAll(['com.android.vending', 'com.example.player']));
      expect(offered, isNot(contains('com.tcl.tv')));
      expect(offered, isNot(contains('com.android.tv.settings')));
      expect(offered, isNot(contains('com.leanbitlab.ltvL.fork')));
    });

    test('completing it makes the chosen apps the Favorites row, in order, and ends the onboarding', () async {
      final service = await start([
        _app('io.gh.reisxd.tizentube.cobalt', 'TizenTube'),
        _app('com.spotify.tv.android', 'Spotify'),
        _app('com.example.other', 'Other'),
      ]);
      final byPackage = {for (final a in service.applications) a.packageName: a};

      await service.completeOnboarding([byPackage['com.example.other']!, byPackage['com.spotify.tv.android']!]);

      expect(service.onboardingActive, isFalse);
      expect(favorites(service).applications.map((a) => a.packageName), ['com.example.other', 'com.spotify.tv.android']);
    });

    test('choosing again from the settings replaces the old favorites and can be cancelled', () async {
      final service = await start([
        _app('io.gh.reisxd.tizentube.cobalt', 'TizenTube'),
        _app('com.spotify.tv.android', 'Spotify'),
        _app('com.example.other', 'Other'),
      ]);
      final byPackage = {for (final a in service.applications) a.packageName: a};
      await service.completeOnboarding([byPackage['io.gh.reisxd.tizentube.cobalt']!]);

      service.restartOnboarding();
      expect(service.onboardingActive, isTrue);
      expect(service.onboardingSuggestions.map((a) => a.packageName), ['io.gh.reisxd.tizentube.cobalt']);

      service.cancelOnboarding();
      expect(service.onboardingActive, isFalse);
      expect(favorites(service).applications.map((a) => a.packageName), ['io.gh.reisxd.tizentube.cobalt']);

      service.restartOnboarding();
      await service.completeOnboarding([byPackage['com.example.other']!]);
      expect(favorites(service).applications.map((a) => a.packageName), ['com.example.other']);
    });
  });

  test('default favorites list covers the six apps from the old home screen', () {
    expect(AppsService.defaultFavoritePackages, [
      'io.gh.reisxd.tizentube.cobalt',
      'com.plexapp.android',
      'com.amazon.amazonvideo.livingroom',
      'com.netflix.ninja',
      'com.spotify.tv.android',
      'tv.twitch.android.app',
    ]);
  });
}

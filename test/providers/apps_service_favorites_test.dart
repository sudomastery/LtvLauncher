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
    SharedPreferences.setMockInitialValues({});
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

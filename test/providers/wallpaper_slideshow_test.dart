/*
 * Tests for the wallpaper slideshow (pictures read from <external files dir>/wallpapers).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:convert';
import 'dart:io';

import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../mocks.mocks.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String documents;
  final String external;

  _FakePathProvider(this.documents, this.external);

  @override
  Future<String?> getApplicationDocumentsPath() async => documents;

  @override
  Future<String?> getExternalStoragePath() async => external;
}

// A valid 1x1 PNG.
final _png = base64Decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==");

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory folder;
  late MockSettingsService settings;
  late MockFLauncherChannel channel;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp("slideshow_test");
    final documents = await Directory("${temp.path}/documents").create();
    final external = await Directory("${temp.path}/external").create();
    folder = Directory("${external.path}/wallpapers");
    PathProviderPlatform.instance = _FakePathProvider(documents.path, external.path);
    settings = MockSettingsService();
    channel = MockFLauncherChannel();
    when(settings.timeBasedWallpaperEnabled).thenReturn(false);
    when(settings.wallpaperSlideshowMinutes).thenReturn(15);
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test("creates the pictures folder and shows no wallpaper when the slideshow is off", () async {
    when(settings.wallpaperSlideshowEnabled).thenReturn(false);

    final service = WallpaperService(channel, settings);
    await _waitFor(() => folder.existsSync());

    expect(folder.existsSync(), isTrue);
    expect(service.wallpaper, isNull);
    service.dispose();
  });

  test("shows a picture from the folder, ignores other files and moves on when rescanned", () async {
    when(settings.wallpaperSlideshowEnabled).thenReturn(true);
    await folder.create(recursive: true);
    for (final name in ["a.png", "b.PNG", "c.png"]) {
      await File("${folder.path}/$name").writeAsBytes(_png);
    }
    await File("${folder.path}/notes.txt").writeAsString("not a picture");

    final service = WallpaperService(channel, settings);
    await _waitFor(() => service.wallpaper != null);

    expect(service.wallpaper, isNotNull);
    expect(service.slideshowPictureCount, 3);
    expect(service.slideshowFolderPath, folder.path);

    final firstVersion = service.version;
    await service.rescanSlideshow();
    expect(service.version, greaterThan(firstVersion));
    service.dispose();
  });

  test("an empty folder leaves the normal wallpaper logic in charge", () async {
    when(settings.wallpaperSlideshowEnabled).thenReturn(true);
    await folder.create(recursive: true);

    final service = WallpaperService(channel, settings);
    await _waitFor(() => service.slideshowFolderPath != null);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(service.slideshowPictureCount, 0);
    expect(service.wallpaper, isNull);
    service.dispose();
  });
}

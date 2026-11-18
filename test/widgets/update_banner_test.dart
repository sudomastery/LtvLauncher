/*
 * Tests for the update banner.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:convert';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/update_service.dart';
import 'package:flauncher/widgets/update_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

Future<(UpdateService, SettingsService, MockFLauncherChannel)> _pump(WidgetTester tester, {String installed = '2026.10.27'}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsService(await SharedPreferences.getInstance());
  final channel = MockFLauncherChannel();
  when(channel.getSupportedAbis()).thenAnswer((_) async => ['armeabi-v7a']);
  when(channel.getUpdateDirectory()).thenAnswer((_) async => '/tmp/none');
  final update = UpdateService(
    channel,
    settings: settings,
    currentVersion: () async => installed,
    get: (uri) async => uri.path.endsWith('.sha256')
        ? 'a' * 64
        : jsonEncode({
            'tag_name': 'v2026.11.18',
            'body': '',
            'assets': [
              {'name': 'LTvLauncher-Enhanced-armeabi-v7a.apk', 'browser_download_url': 'https://example.test/a.apk'},
              {'name': 'LTvLauncher-Enhanced-armeabi-v7a.apk.sha256', 'browser_download_url': 'https://example.test/a.sha256'},
            ],
          }),
  );
  await update.autoCheck();

  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settings),
      ChangeNotifierProvider<UpdateService>.value(value: update),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Stack(children: [UpdateBanner()])),
    ),
  ));
  await tester.pump();
  return (update, settings, channel);
}

void main() {
  testWidgets('offers Update, Ignore and Never show updates for a newer version', (tester) async {
    await _pump(tester);

    expect(find.text('Update available: 2026.11.18'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
    expect(find.text('Never show updates'), findsOneWidget);
  });

  testWidgets('shows nothing when the app is already up to date', (tester) async {
    await _pump(tester, installed: '2026.11.18');
    expect(find.textContaining('Update available'), findsNothing);
    expect(find.text('Ignore'), findsNothing);
  });

  testWidgets('Ignore hides it and remembers that version', (tester) async {
    final (update, settings, _) = await _pump(tester);

    await tester.tap(find.text('Ignore'));
    await tester.pump();

    expect(find.textContaining('Update available'), findsNothing);
    expect(settings.ignoredUpdateVersion, '2026.11.18');
    expect(update.bannerVisible, isFalse);
  });

  testWidgets('Never show updates switches the banner and the automatic checks off', (tester) async {
    final (_, settings, _) = await _pump(tester);

    await tester.tap(find.text('Never show updates'));
    await tester.pump();

    expect(find.textContaining('Update available'), findsNothing);
    expect(settings.updateChecksEnabled, isFalse);
  });

  testWidgets('Update starts the download and install', (tester) async {
    final (update, _, channel) = await _pump(tester);
    when(channel.installUpdate(any, any)).thenAnswer((_) async => {'ok': true, 'message': 'Success'});

    await tester.tap(find.text('Update'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(update.status, anyOf(UpdateStatus.downloading, UpdateStatus.installing, UpdateStatus.installed, UpdateStatus.error));
    expect(find.text('Ignore'), findsNothing); // the choices give way to the progress
  });
}

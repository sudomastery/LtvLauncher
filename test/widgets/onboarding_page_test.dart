/*
 * Tests for the first-run "pick your most used apps" screen.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:typed_data';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.dart';
import '../mocks.mocks.dart';

Future<MockAppsService> _pump(WidgetTester tester, List<App> choices, {List<App> suggested = const []}) async {
  final apps = MockAppsService();
  when(apps.onboardingChoices).thenReturn(choices);
  when(apps.onboardingSuggestions).thenReturn(suggested);
  when(apps.getAppBanner(any)).thenAnswer((_) async => Uint8List(0));
  when(apps.getAppIcon(any)).thenAnswer((_) async => Uint8List(0));
  when(apps.completeOnboarding(any)).thenAnswer((_) async {});

  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(ChangeNotifierProvider<AppsService>.value(
    value: apps,
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: OnboardingPage()),
    ),
  ));
  await tester.pumpAndSettle();
  return apps;
}

List<App> _apps(int n) => [for (var i = 1; i <= n; i++) fakeApp(packageName: "com.example.app$i", name: "App $i", version: "1.0.0")];

void main() {
  testWidgets("asks for at least three apps and keeps Done unavailable until then", (tester) async {
    final apps = await _pump(tester, _apps(6));

    expect(find.text("Welcome! Pick your most used apps"), findsOneWidget);
    expect(find.textContaining("Pick at least 3"), findsOneWidget);

    await tester.tap(find.text("App 1"));
    await tester.tap(find.text("App 2"));
    await tester.pump();
    await tester.tap(find.text("Done"));
    await tester.pump();
    verifyNever(apps.completeOnboarding(any));
    expect(find.textContaining("Pick at least 3"), findsOneWidget);
  });

  testWidgets("saves the chosen apps in the order they were picked once three are selected", (tester) async {
    final all = _apps(6);
    final apps = await _pump(tester, all);

    await tester.tap(find.text("App 4"));
    await tester.tap(find.text("App 2"));
    await tester.tap(find.text("App 5"));
    await tester.pump();
    expect(find.textContaining("Pick at least"), findsNothing);
    expect(find.text("3 selected"), findsOneWidget);

    await tester.tap(find.text("Done"));
    await tester.pump();

    final saved = verify(apps.completeOnboarding(captureAny)).captured.single as List<App>;
    expect(saved.map((a) => a.packageName), ["com.example.app4", "com.example.app2", "com.example.app5"]);
  });

  testWidgets("starts with the suggested apps ticked and lets one be unticked", (tester) async {
    final all = _apps(5);
    final apps = await _pump(tester, all, suggested: [all[0], all[1], all[2]]);
    expect(find.text("3 selected"), findsOneWidget);

    await tester.tap(find.text("App 2"));
    await tester.pump();
    expect(find.textContaining("Pick at least 3"), findsOneWidget);

    await tester.tap(find.text("App 5"));
    await tester.pump();
    await tester.tap(find.text("Done"));
    await tester.pump();

    final saved = verify(apps.completeOnboarding(captureAny)).captured.single as List<App>;
    expect(saved.map((a) => a.packageName), ["com.example.app1", "com.example.app3", "com.example.app5"]);
  });

  testWidgets("a TV with fewer than three apps only needs what it has", (tester) async {
    final apps = await _pump(tester, _apps(2));

    await tester.tap(find.text("App 1"));
    await tester.tap(find.text("App 2"));
    await tester.pump();
    await tester.tap(find.text("Done"));
    await tester.pump();

    verify(apps.completeOnboarding(any)).called(1);
  });
}

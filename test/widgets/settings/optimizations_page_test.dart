/*
 * Tests for the Optimizations page (Play Store switch).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/settings/optimizations_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

Future<MockFLauncherChannel> _pump(WidgetTester tester, {required bool playStoreEnabled}) async {
  final channel = MockFLauncherChannel();
  when(channel.isPackageEnabled(OptimizationsPage.playStorePackage)).thenAnswer((_) async => playStoreEnabled);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: OptimizationsPage(channel: channel)),
  ));
  await tester.pumpAndSettle();
  return channel;
}

Switch _switch(WidgetTester tester) => tester.widget<Switch>(find.byType(Switch));

void main() {
  testWidgets("switch is off while the Play Store is enabled", (tester) async {
    await _pump(tester, playStoreEnabled: true);
    expect(_switch(tester).value, isFalse);
  });

  testWidgets("switch is on once the Play Store is disabled", (tester) async {
    await _pump(tester, playStoreEnabled: false);
    expect(_switch(tester).value, isTrue);
  });

  testWidgets("turning the switch on asks the system to disable the Play Store", (tester) async {
    final channel = await _pump(tester, playStoreEnabled: true);
    when(channel.setPackageEnabled(OptimizationsPage.playStorePackage, false))
        .thenAnswer((_) async => {'ok': true, 'message': ''});
    when(channel.isPackageEnabled(OptimizationsPage.playStorePackage)).thenAnswer((_) async => false);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    verify(channel.setPackageEnabled(OptimizationsPage.playStorePackage, false)).called(1);
    expect(_switch(tester).value, isTrue);
    expect(find.textContaining("Could not change the setting"), findsNothing);
  });

  testWidgets("shows the reason when the change fails and leaves the switch where it was", (tester) async {
    final channel = await _pump(tester, playStoreEnabled: true);
    when(channel.setPackageEnabled(OptimizationsPage.playStorePackage, false))
        .thenAnswer((_) async => {'ok': false, 'message': 'ConnectException: Connection refused'});

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.textContaining("Could not change the setting"), findsOneWidget);
    expect(find.textContaining("Connection refused"), findsOneWidget);
    expect(_switch(tester).value, isFalse);
  });
}

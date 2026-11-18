/*
 * Tests for the HDMI input shortcuts under the settings icons.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'package:flauncher/models/tv_input.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/tv_inputs_service.dart';
import 'package:flauncher/widgets/input_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

Future<MockTvInputsService> _pump(WidgetTester tester, List<TvInput> inputs, {bool show = true}) async {
  final settings = MockSettingsService();
  when(settings.showInputShortcuts).thenReturn(show);
  final service = MockTvInputsService();
  when(service.inputs).thenReturn(inputs);
  when(service.hasInputs).thenReturn(inputs.isNotEmpty);
  when(service.switchInput(any)).thenAnswer((_) async => true);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settings),
      ChangeNotifierProvider<TvInputsService>.value(value: service),
    ],
    child: const MaterialApp(home: Scaffold(body: InputShortcuts())),
  ));
  await tester.pump();
  return service;
}

void main() {
  final hdmi1 = TvInput(id: 'hdmi1', label: 'HDMI 1', type: TvInputType.hdmi);
  final hdmi2 = TvInput(id: 'hdmi2', label: 'HDMI 2', type: TvInputType.hdmi);
  final tuner = TvInput(id: 'tuner', label: 'Antenna', type: TvInputType.tuner);

  testWidgets("shows one small chip per HDMI input and leaves other inputs out", (tester) async {
    await _pump(tester, [hdmi1, hdmi2, tuner]);

    expect(find.byIcon(Icons.settings_input_hdmi), findsNWidgets(2));
    expect(find.text("1"), findsOneWidget);
    expect(find.text("2"), findsOneWidget);
    expect(find.text("Antenna"), findsNothing);
  });

  testWidgets("pressing a chip switches the TV to that input", (tester) async {
    final service = await _pump(tester, [hdmi1, hdmi2]);

    await tester.tap(find.text("2"));
    await tester.pump();

    verify(service.switchInput('hdmi2')).called(1);
  });

  testWidgets("is hidden when switched off or when the TV has no HDMI inputs", (tester) async {
    await _pump(tester, [hdmi1], show: false);
    expect(find.byIcon(Icons.settings_input_hdmi), findsNothing);
  });

  testWidgets("is hidden when there are no HDMI inputs", (tester) async {
    await _pump(tester, [tuner]);
    expect(find.byIcon(Icons.settings_input_hdmi), findsNothing);
  });
}

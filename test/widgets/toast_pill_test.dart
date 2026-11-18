/*
 * Tests for the floating message pill.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'package:flauncher/widgets/toast_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<OverlayState> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.expand())));
    return Overlay.of(tester.element(find.byType(Scaffold)));
  }

  testWidgets("shows the message in the top right corner and removes itself after about two seconds", (tester) async {
    final overlay = await pump(tester);

    showPillToast(overlay, "Closed: TizenTube");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Closed: TizenTube"), findsOneWidget);
    final center = tester.getCenter(find.text("Closed: TizenTube"));
    final screen = tester.getSize(find.byType(Scaffold));
    expect(center.dx, greaterThan(screen.width * 0.6));
    expect(center.dy, lessThan(screen.height * 0.25));

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text("Closed: TizenTube"), findsNothing);
  });

  testWidgets("is only as wide as its text, not the whole screen", (tester) async {
    final overlay = await pump(tester);

    showPillToast(overlay, "Closed");
    await tester.pump(const Duration(milliseconds: 300));

    final pill = tester.getSize(find.byType(Container).last);
    expect(pill.width, lessThan(tester.getSize(find.byType(Scaffold)).width / 2));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets("does not block taps on what is underneath", (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: ElevatedButton(onPressed: () => taps++, child: const Text("tap me")))),
    ));
    final overlay = Overlay.of(tester.element(find.byType(Scaffold)));

    showPillToast(overlay, "Closed");
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("tap me"));
    await tester.pump();

    expect(taps, 1);
    await tester.pump(const Duration(seconds: 3));
  });
}

import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/back_button_actions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  group('LauncherState handleBackNavigation', () {
    late MockAppsService mockAppsService;
    late MockSettingsService mockSettingsService;
    late LauncherState launcherState;

    setUp(() {
      mockAppsService = MockAppsService();
      when(mockAppsService.onboardingActive).thenReturn(false);
      mockSettingsService = MockSettingsService();
      launcherState = LauncherState();
    });

    Widget createTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AppsService>.value(value: mockAppsService),
          ChangeNotifierProvider<SettingsService>.value(value: mockSettingsService),
          ChangeNotifierProvider<LauncherState>.value(value: launcherState),
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              return GestureDetector(
                onTap: () {
                  launcherState.handleBackNavigation(context);
                },
                child: const Text('Tap Me'),
              );
            },
          ),
        ),
      );
    }

    testWidgets('handleBackNavigation opens clock when action is BACK_BUTTON_ACTION_CLOCK', (WidgetTester tester) async {
      when(mockSettingsService.backButtonAction).thenReturn(BACK_BUTTON_ACTION_CLOCK);
      when(mockAppsService.isDefaultLauncher()).thenAnswer((_) async => true);

      // Force refresh to apply isDefaultLauncher locally if not kDebugMode
      await launcherState.refresh(mockAppsService);

      expect(launcherState.launcherVisible, isTrue);

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Tap Me'));
      await tester.pumpAndSettle();

      expect(launcherState.launcherVisible, isFalse);
    });

    testWidgets('handleBackNavigation starts screensaver when action is BACK_BUTTON_ACTION_SCREENSAVER', (WidgetTester tester) async {
      when(mockSettingsService.backButtonAction).thenReturn(BACK_BUTTON_ACTION_SCREENSAVER);
      when(mockAppsService.isDefaultLauncher()).thenAnswer((_) async => true);
      when(mockAppsService.startAmbientMode()).thenAnswer((_) async {});

      // Force refresh
      await launcherState.refresh(mockAppsService);

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Tap Me'));
      await tester.pumpAndSettle();

      verify(mockAppsService.startAmbientMode()).called(1);
    });

    testWidgets('handleBackNavigation does nothing when action is BACK_BUTTON_ACTION_NOTHING', (WidgetTester tester) async {
      when(mockSettingsService.backButtonAction).thenReturn(BACK_BUTTON_ACTION_NOTHING);
      when(mockAppsService.isDefaultLauncher()).thenAnswer((_) async => true);

      // Force refresh
      await launcherState.refresh(mockAppsService);

      expect(launcherState.launcherVisible, isTrue);

      await tester.pumpWidget(createTestWidget());
      await tester.tap(find.text('Tap Me'));
      await tester.pumpAndSettle();

      expect(launcherState.launcherVisible, isTrue);
      verifyNever(mockAppsService.startAmbientMode());
    });
  });

  group('LauncherState toggleLauncherVisibility', () {
    late LauncherState launcherState;

    setUp(() {
      launcherState = LauncherState();
    });

    test('initial launcherVisible state is true', () {
      expect(launcherState.launcherVisible, isTrue);
    });

    test('toggleLauncherVisibility changes launcherVisible from true to false', () {
      launcherState.toggleLauncherVisibility();
      expect(launcherState.launcherVisible, isFalse);
    });

    test('toggleLauncherVisibility changes launcherVisible from false back to true', () {
      launcherState.toggleLauncherVisibility();
      expect(launcherState.launcherVisible, isFalse);

      launcherState.toggleLauncherVisibility();
      expect(launcherState.launcherVisible, isTrue);
    });

    test('toggleLauncherVisibility calls notifyListeners', () {
      bool listenersNotified = false;
      launcherState.addListener(() {
        listenersNotified = true;
      });

      launcherState.toggleLauncherVisibility();

      expect(listenersNotified, isTrue);
    });
  });

  group('LauncherState minimalist mode', () {
    testWidgets('starts hidden when switched on and shows everything when switched off', (tester) async {
      final state = LauncherState();
      expect(state.minimalistHidden, isFalse);

      state.setMinimalistActive(true);
      expect(state.minimalistHidden, isTrue);

      state.setMinimalistActive(false);
      expect(state.minimalistHidden, isFalse);
      state.dispose();
    });

    testWidgets('revealed controls hide again after one minute without a key press', (tester) async {
      final state = LauncherState();
      state.setMinimalistActive(true);

      state.revealMinimalist();
      expect(state.minimalistHidden, isFalse);

      await tester.pump(const Duration(seconds: 59));
      expect(state.minimalistHidden, isFalse);

      await tester.pump(const Duration(seconds: 2));
      expect(state.minimalistHidden, isTrue);
      state.dispose();
    });

    testWidgets('every key press restarts the one minute countdown', (tester) async {
      final state = LauncherState();
      state.setMinimalistActive(true);
      state.revealMinimalist();

      await tester.pump(const Duration(seconds: 40));
      state.bumpMinimalistActivity();
      await tester.pump(const Duration(seconds: 40));
      expect(state.minimalistHidden, isFalse); // 80 s since the reveal, but only 40 s since the last key

      await tester.pump(const Duration(seconds: 25));
      expect(state.minimalistHidden, isTrue);
      state.dispose();
    });

    testWidgets('does not hide while a panel is open on top, and hides once it is closed', (tester) async {
      final state = LauncherState();
      var somethingOnTop = true;
      state.minimalistCanHide = () => !somethingOnTop;
      state.setMinimalistActive(true);
      state.revealMinimalist();

      await tester.pump(const Duration(seconds: 61));
      expect(state.minimalistHidden, isFalse);

      somethingOnTop = false;
      await tester.pump(const Duration(seconds: 61));
      expect(state.minimalistHidden, isTrue);
      state.dispose();
    });

    testWidgets('going back to the bare wallpaper also closes the all apps view', (tester) async {
      final state = LauncherState();
      state.setMinimalistActive(true);
      state.revealMinimalist();
      state.setAllAppsOpen(true);

      await tester.pump(const Duration(seconds: 61));

      expect(state.minimalistHidden, isTrue);
      expect(state.allAppsOpen, isFalse);
      state.dispose();
    });
  });
}

/*
 * FLauncher
 * Copyright (C) 2021  Oscar Rojas
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../widgets/settings/back_button_actions.dart';
import 'apps_service.dart';
import 'update_service.dart';

class LauncherState extends ChangeNotifier
{
  bool _isDefaultLauncher;
  bool _launcherVisible;

  DateTime? _suppressBackUntil;
  bool _allAppsOpen = false;

  bool  get isDefaultLauncher => _isDefaultLauncher;
  bool  get launcherVisible => _launcherVisible;

  /// True while the full apps view is open on top of the showcase home screen.
  bool  get allAppsOpen => _allAppsOpen;

  void setAllAppsOpen(bool open) {
    if (_allAppsOpen == open) return;
    _allAppsOpen = open;
    notifyListeners();
  }

  /// How long the controls stay on screen in minimalist mode after the last key press.
  final Duration minimalistHideAfter;

  LauncherState({this.minimalistHideAfter = const Duration(minutes: 1)})
      : _isDefaultLauncher = false, _launcherVisible = true;

  // ----- Minimalist mode: only the wallpaper until a key is pressed -----

  bool _minimalistHidden = false;
  Timer? _minimalistTimer;

  /// Lets the home screen postpone hiding while a dialog or panel is open on top of it.
  bool Function() minimalistCanHide = () => true;

  /// True while the controls are hidden and only the wallpaper shows.
  bool get minimalistHidden => _minimalistHidden;

  /// Turns the behaviour on (starts with the controls hidden) or off (controls always shown).
  void setMinimalistActive(bool active) {
    _minimalistTimer?.cancel();
    if (active) {
      hideMinimalistNow(force: true);
    } else if (_minimalistHidden) {
      _minimalistHidden = false;
      notifyListeners();
    }
  }

  /// Hides the controls, unless something is open on top of them (then it tries again a minute later).
  void hideMinimalistNow({bool force = false}) {
    _minimalistTimer?.cancel();
    if (!force && !minimalistCanHide()) {
      _scheduleMinimalistHide();
      return;
    }
    _allAppsOpen = false;
    if (!_minimalistHidden) {
      _minimalistHidden = true;
    }
    notifyListeners();
  }

  /// Shows the controls and starts the countdown to hide them again.
  void revealMinimalist() {
    final changed = _minimalistHidden;
    _minimalistHidden = false;
    _scheduleMinimalistHide();
    if (changed) notifyListeners();
  }

  /// Any key press while the controls are showing restarts the countdown.
  void bumpMinimalistActivity() {
    if (!_minimalistHidden) _scheduleMinimalistHide();
  }

  void _scheduleMinimalistHide() {
    _minimalistTimer?.cancel();
    _minimalistTimer = Timer(minimalistHideAfter, () => hideMinimalistNow());
  }

  @override
  void dispose() {
    _minimalistTimer?.cancel();
    super.dispose();
  }

  void toggleLauncherVisibility() {
    _launcherVisible = !_launcherVisible;
    notifyListeners();
  }

  void suppressBackNavigation() {
    _suppressBackUntil = DateTime.now().add(const Duration(milliseconds: 500));
  }

  Future<void> refresh(AppsService appsService) async {
    _isDefaultLauncher = await appsService.isDefaultLauncher();
    notifyListeners();
  }

  void handleBackNavigation(BuildContext context) {
    if (_allAppsOpen) {
      setAllAppsOpen(false);
      return;
    }
    try {
      final update = context.read<UpdateService>();
      if (update.bannerVisible) {
        update.dismissForNow();
        return;
      }
    } catch (_) {
      // No update service in this context (some tests): nothing to dismiss.
    }
    final apps = context.read<AppsService>();
    if (apps.onboardingActive) {
      apps.cancelOnboarding();
      return;
    }
    if (_suppressBackUntil != null && DateTime.now().isBefore(_suppressBackUntil!)) {
      _suppressBackUntil = null;
      return;
    }
    AppsService appsService = context.read<AppsService>();
    LauncherState launcherState = context.read<LauncherState>();
    SettingsService settingsService = context.read<SettingsService>();

    if (kDebugMode || launcherState.isDefaultLauncher) {
      launcherState.refresh(appsService);
      String action = settingsService.backButtonAction;

      switch (action) {
        case BACK_BUTTON_ACTION_CLOCK:
          launcherState.toggleLauncherVisibility();
          break;
        case BACK_BUTTON_ACTION_SCREENSAVER:
          appsService.startAmbientMode();
          break;
      }
    }
    else {
      SystemNavigator.pop();
    }
  }
}
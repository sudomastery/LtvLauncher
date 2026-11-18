/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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


import 'package:flauncher/actions.dart';
import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/apps_grid.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/launcher_alternative_view.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/input_shortcuts.dart';
import 'package:flauncher/widgets/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/widgets/continue_watching_row.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/l10n/app_localizations.dart';

import 'models/category.dart';

class FLauncher extends StatefulWidget {
  const FLauncher({super.key});

  @override
  State<FLauncher> createState() => _FLauncherState();
}

class _FLauncherState extends State<FLauncher> with WidgetsBindingObserver {
  final GlobalKey<FocusAwareAppBarState> _appBarKey = GlobalKey();
  bool _lastMinimalist = false;
  // Kept from initState: looking things up through the context is not allowed in dispose().
  late final SettingsService _settings;
  late final LauncherState _launcherState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addEarlyKeyEventHandler(_onEarlyKey);
    _settings = context.read<SettingsService>();
    _launcherState = context.read<LauncherState>();
    _settings.addListener(_syncMinimalist);
    // The controls only hide while nothing (a panel, a dialog) is open on top of the home screen.
    _launcherState.minimalistCanHide = () => mounted && (ModalRoute.of(context)?.isCurrent ?? true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncMinimalist(force: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeEarlyKeyEventHandler(_onEarlyKey);
    _settings.removeListener(_syncMinimalist);
    _launcherState.minimalistCanHide = () => true;
    super.dispose();
  }

  void _syncMinimalist({bool force = false}) {
    if (!mounted) return;
    final enabled = context.read<SettingsService>().minimalistMode;
    if (force || enabled != _lastMinimalist) {
      _lastMinimalist = enabled;
      context.read<LauncherState>().setMinimalistActive(enabled);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from another app: start again from the bare wallpaper.
    if (state == AppLifecycleState.resumed && mounted && context.read<SettingsService>().minimalistMode) {
      context.read<LauncherState>().setMinimalistActive(true);
    }
  }

  static final _wakeKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  };

  /// Runs before the buttons see a key. In minimalist mode the first arrow or select press only brings the
  /// controls back, so nothing is moved or launched while it is invisible.
  KeyEventResult _onEarlyKey(KeyEvent event) {
    if (!mounted) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (!context.read<SettingsService>().minimalistMode) return KeyEventResult.ignored;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return KeyEventResult.ignored;

    final launcher = context.read<LauncherState>();
    if (launcher.minimalistHidden) {
      if (_wakeKeys.contains(event.logicalKey)) {
        launcher.revealMinimalist();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    launcher.bumpMinimalistActivity();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      MoveFocusToSettingsIntent: CallbackAction<MoveFocusToSettingsIntent>(
        onInvoke: (_) => _appBarKey.currentState?.focusSettings(),
      ),
    },
    child: FocusTraversalGroup(
      policy: RowByRowTraversalPolicy(),
      child: Stack(
        children: [
          RepaintBoundary(
            child: Consumer<WallpaperService>(
              builder: (ctx, wallpaperService, __) => _wallpaper(ctx, wallpaperService,
                  showcase: _showcaseActive(ctx),
                  bare: ctx.select<LauncherState, bool>((state) => state.minimalistHidden))
            ),
          ),
          Consumer<LauncherState>(
            builder: (_, state, child) => Visibility(
              child: child!,
              replacement: const Center(
                child: AlternativeLauncherView()
              ),
              visible: state.launcherVisible
            ),
            child: _MinimalistFade(child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: FocusAwareAppBar(key: _appBarKey),
              body: Column(
                children: [
                  const InputShortcuts(),
                  Expanded(
                    child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Consumer<AppsService>(
                  builder: (context, appsService, _) {
                    if (appsService.initialized) {
                      final showcaseFavorites = _showcaseFavorites(context, appsService);
                      if (showcaseFavorites != null) {
                        return _showcase(context, showcaseFavorites);
                      }
                      return Selector<WatchNextService, bool>(
                        selector: (_, watchNext) => watchNext.programs.isNotEmpty,
                        builder: (context, hasContinuingPrograms, _) =>
                            Selector<SettingsService, ({bool show, int order})>(
                              selector: (_, settings) => (
                                show: settings.showContinueWatching,
                                order: settings.continueWatchingOrder,
                              ),
                              builder: (context, cwSettings, _) =>
                                  SingleChildScrollView(
                                    physics: const ClampingScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _sections(
                                            appsService.launcherSections,
                                            continueWatchingActive:
                                                cwSettings.show &&
                                                hasContinuingPrograms,
                                            continueWatchingOrder:
                                                cwSettings.order),
                                      ],
                                    ),
                                  ),
                            ),
                    );
                    }
                    else {
                      return _emptyState(context);
                    }
                  }
                )
              )
                  ),
                ],
              )
            ))
          ),
          // First run (or "Choose favorite apps" in the settings): pick the apps for the home screen.
          Consumer<AppsService>(
            builder: (_, apps, __) => apps.initialized && apps.onboardingActive
                ? const OnboardingPage()
                : const SizedBox.shrink(),
          ),
        ]
      )
    ),
  );

  /// The Favorites row when the showcase home screen should be shown, otherwise null.
  Category? _showcaseFavorites(BuildContext context, AppsService appsService) {
    final enabled = context.select<SettingsService, bool>((settings) => settings.showcaseLayout);
    final allAppsOpen = context.select<LauncherState, bool>((state) => state.allAppsOpen);
    if (!enabled || allAppsOpen) return null;
    for (final section in appsService.launcherSections) {
      if (section is Category && section.name.toLowerCase() == 'favorites' && section.applications.isNotEmpty) {
        return section;
      }
    }
    return null;
  }

  bool _showcaseActive(BuildContext context) =>
      _showcaseFavorites(context, context.watch<AppsService>()) != null;

  /// Wallpaper on show, one row of favorites along the bottom. Down opens the full apps view, Back returns.
  Widget _showcase(BuildContext context, Category favorites) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
          context.read<LauncherState>().setAllAppsOpen(true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          const Spacer(),
          CategoryRow(
            key: Key("showcase_${favorites.id}"),
            category: favorites,
            applications: favorites.applications,
            isFirstSection: true,
            showTitle: false,
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _sections(
    List<LauncherSection> sections, {
    bool continueWatchingActive = false,
    int continueWatchingOrder = 0,
  }) {
    List<Widget> children = [];
    bool firstCategoryFound = false;
    bool cwInserted = false;

    int sectionIdx = 0;
    for (var section in sections) {
      if (continueWatchingActive && !cwInserted && sectionIdx == continueWatchingOrder) {
        final bool isFirstSection = !firstCategoryFound;
        children.add(ContinueWatchingRow(isFirstSection: isFirstSection));
        cwInserted = true;
        firstCategoryFound = true;
      }

      final Key sectionKey = Key(section.id.toString());

      if (section is LauncherSpacer) {
        children.add(SizedBox(key: sectionKey, height: section.height.toDouble()));
        sectionIdx++;
        continue;
      }

      Category category = section as Category;
      Widget categoryWidget;

      // Pass isFirstSection only to the first category found
      bool isFirstSection = !firstCategoryFound;
      if (isFirstSection) firstCategoryFound = true;

      switch (category.type) {
        case CategoryType.row:
          categoryWidget = CategoryRow(
              key: sectionKey,
              category: category,
              applications: category.applications,
              isFirstSection: isFirstSection
          );
          break;
        case CategoryType.grid:
          categoryWidget = AppsGrid(
              key: sectionKey,
              category: category,
              applications: category.applications,
              isFirstSection: isFirstSection
          );
          break;
      }

      children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: categoryWidget
      ));
      sectionIdx++;
    }

    if (continueWatchingActive && !cwInserted) {
      final bool isFirstSection = !firstCategoryFound;
      children.add(ContinueWatchingRow(isFirstSection: isFirstSection));
      cwInserted = true;
      firstCategoryFound = true;
    }

    return Column(children: children);
  }

  Widget _wallpaper(BuildContext context, WallpaperService wallpaperService, {bool showcase = false, bool bare = false}) {
    Widget background;
    if (wallpaperService.wallpaper != null) {
      final physicalSize = MediaQuery.sizeOf(context);
      background = AnimatedSwitcher(
        duration: const Duration(milliseconds: 700),
        child: Image(
          image: wallpaperService.wallpaper!,
          key: Key("background_${wallpaperService.version}"),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          height: physicalSize.height,
          width: physicalSize.width
        ),
      );
    }
    else {
      background = Container(key: const Key("background"), decoration: BoxDecoration(gradient: wallpaperService.gradient.gradient));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        // In minimalist mode, with the controls hidden, the picture is shown as it is, without the dimming.
        AnimatedOpacity(
          duration: const Duration(milliseconds: 400),
          opacity: bare ? 0.0 : 1.0,
          child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Showcase keeps the picture bright and only darkens the bottom where the apps sit.
              colors: showcase
                  ? [
                      Colors.black.withOpacity(0.10),
                      Colors.black.withOpacity(0.0),
                      Colors.black.withOpacity(0.0),
                      Colors.black.withOpacity(0.70),
                    ]
                  : [
                      Colors.black.withOpacity(0.35),
                      Colors.black.withOpacity(0.15),
                      Colors.black.withOpacity(0.45),
                    ],
              stops: showcase ? const [0.0, 0.25, 0.60, 1.0] : null,
            ),
          ),
        ),
        ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(localizations.loading, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

/// Fades the controls out (and stops them taking touches) while minimalist mode has them hidden.
class _MinimalistFade extends StatelessWidget {
  final Widget child;

  const _MinimalistFade({required this.child});

  @override
  Widget build(BuildContext context) {
    final hidden = context.select<LauncherState, bool>((state) => state.minimalistHidden);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: hidden ? 0.0 : 1.0,
      child: IgnorePointer(ignoring: hidden, child: child),
    );
  }
}

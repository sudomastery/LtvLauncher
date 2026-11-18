/*
 * First-run screen: pick your most used apps so the home screen is not filled with everything.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:math';
import 'dart:typed_data';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Full-screen picker. Choose at least [AppsService.onboardingMinimumApps] apps; they become the
/// Favorites row on the home screen, in the order they were chosen.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late final List<App> _choices;
  late final List<String> _selected;
  late final int _minimum;

  @override
  void initState() {
    super.initState();
    final apps = context.read<AppsService>();
    _choices = apps.onboardingChoices;
    _selected = apps.onboardingSuggestions.map((app) => app.packageName).toList();
    _minimum = min(AppsService.onboardingMinimumApps, _choices.length);
  }

  bool get _ready => _selected.length >= _minimum;

  void _toggle(App app) {
    setState(() {
      if (!_selected.remove(app.packageName)) _selected.add(app.packageName);
    });
  }

  Future<void> _done() async {
    if (!_ready) return;
    final byPackage = {for (final app in _choices) app.packageName: app};
    await context.read<AppsService>().completeOnboarding([
      for (final pkg in _selected)
        if (byPackage[pkg] != null) byPackage[pkg]!,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;

    return FocusScope(
      autofocus: true,
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: SizedBox.expand(
          child: Material(
            color: const Color(0xFF0B0B10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(48, 32, 48, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(localizations.onboardingTitle, style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(localizations.onboardingSubtitle, style: textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                  const SizedBox(height: 18),
                  Expanded(
                    child: GridView.builder(
                      clipBehavior: Clip.none,
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 190,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 16 / 10,
                      ),
                      itemCount: _choices.length,
                      itemBuilder: (context, index) {
                        final app = _choices[index];
                        return _AppChoice(
                          key: ValueKey(app.packageName),
                          app: app,
                          selected: _selected.contains(app.packageName),
                          autofocus: index == 0,
                          accent: accent,
                          onToggle: () => _toggle(app),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        _ready
                            ? "${_selected.length} ${localizations.onboardingSelected}"
                            : "${localizations.onboardingNeedMore} $_minimum  (${_selected.length} ${localizations.onboardingSelected})",
                        style: textTheme.bodyMedium?.copyWith(color: _ready ? Colors.white : Colors.white70),
                      ),
                      const Spacer(),
                      _DoneButton(enabled: _ready, accent: accent, label: localizations.onboardingDone, onPressed: _done),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppChoice extends StatefulWidget {
  final App app;
  final bool selected;
  final bool autofocus;
  final Color accent;
  final VoidCallback onToggle;

  const _AppChoice({
    super.key,
    required this.app,
    required this.selected,
    required this.autofocus,
    required this.accent,
    required this.onToggle,
  });

  @override
  State<_AppChoice> createState() => _AppChoiceState();
}

class _AppChoiceState extends State<_AppChoice> {
  bool _focused = false;
  late final Future<Uint8List> _banner = _loadBanner();

  Future<Uint8List> _loadBanner() async {
    final apps = context.read<AppsService>();
    final banner = await apps.getAppBanner(widget.app.packageName);
    return banner.isNotEmpty ? banner : await apps.getAppIcon(widget.app.packageName);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onToggle()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onToggle()),
      },
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (hasFocus) {
          setState(() => _focused = hasFocus);
          if (hasFocus) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 100));
        },
        child: GestureDetector(
          onTap: widget.onToggle,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            scale: _focused ? 1.05 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _focused ? widget.accent : (selected ? widget.accent.withOpacity(0.7) : Colors.white12),
                  width: _focused || selected ? 2 : 1,
                ),
                boxShadow: _focused ? [BoxShadow(color: widget.accent.withOpacity(0.5), blurRadius: 14, spreadRadius: 1)] : const [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: selected || _focused ? 1.0 : 0.55,
                      child: FutureBuilder<Uint8List>(
                        future: _banner,
                        builder: (context, snapshot) {
                          final bytes = snapshot.data;
                          if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
                          return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        color: Colors.black.withOpacity(0.55),
                        child: Text(
                          widget.app.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          decoration: BoxDecoration(color: widget.accent, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(3),
                          child: const Icon(Icons.check, size: 16, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatefulWidget {
  final bool enabled;
  final Color accent;
  final String label;
  final VoidCallback onPressed;

  const _DoneButton({required this.enabled, required this.accent, required this.label, required this.onPressed});

  @override
  State<_DoneButton> createState() => _DoneButtonState();
}

class _DoneButtonState extends State<_DoneButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => enabled ? widget.onPressed() : null),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => enabled ? widget.onPressed() : null),
      },
      child: Focus(
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        child: GestureDetector(
          onTap: enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
            decoration: BoxDecoration(
              color: enabled ? widget.accent.withOpacity(_focused ? 0.9 : 0.55) : Colors.white10,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _focused ? Colors.white : Colors.white24, width: 2),
              boxShadow: _focused && enabled ? [BoxShadow(color: widget.accent.withOpacity(0.55), blurRadius: 16)] : const [],
            ),
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: enabled ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

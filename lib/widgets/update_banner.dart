/*
 * Banner offering a newer version of the launcher: Update, Ignore, or Never show updates.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/update_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Floats at the top centre of the home screen while an update is on offer. It takes the remote focus
/// so Select means "Update"; Right reaches Ignore and Never; Back hides it until the next start.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final update = context.watch<UpdateService>();
    if (!update.bannerVisible) return const SizedBox.shrink();

    final localizations = AppLocalizations.of(context)!;
    final accent = Theme.of(context).colorScheme.primary;
    final textTheme = Theme.of(context).textTheme;
    final version = update.latest?.version ?? '';

    String text;
    List<Widget> actions;
    switch (update.status) {
      case UpdateStatus.downloading:
        text = "${localizations.updatesDownloading} ${(update.progress * 100).round()}%";
        actions = const [];
        break;
      case UpdateStatus.installing:
        text = localizations.updatesInstalling;
        actions = const [];
        break;
      case UpdateStatus.installed:
        text = localizations.updatesInstalled;
        actions = [_BannerButton(label: localizations.updatesClose, accent: accent, onPressed: update.dismissForNow)];
        break;
      case UpdateStatus.error:
        text = "${localizations.updatesFailed}: ${update.error ?? ''}";
        actions = [
          _BannerButton(label: localizations.updatesRetry, accent: accent, primary: true, onPressed: update.downloadAndInstall),
          _BannerButton(label: localizations.updatesClose, accent: accent, onPressed: update.dismissForNow),
        ];
        break;
      default:
        text = "${localizations.updatesAvailable}: $version";
        actions = [
          _BannerButton(
              label: localizations.updatesUpdateNow,
              accent: accent,
              primary: true,
              autofocus: true,
              onPressed: update.downloadAndInstall),
          _BannerButton(label: localizations.updatesIgnore, accent: accent, onPressed: update.ignoreThisVersion),
          _BannerButton(label: localizations.updatesNever, accent: accent, onPressed: update.neverShowUpdates),
        ];
    }

    return FocusScope(
      autofocus: true,
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 64),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 760),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111).withOpacity(0.94),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: accent.withOpacity(0.6), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(0.35), blurRadius: 18, spreadRadius: 1),
                    const BoxShadow(color: Colors.black54, blurRadius: 12),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(update.status == UpdateStatus.error ? Icons.error_outline : Icons.system_update, color: accent, size: 22),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(text, style: textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    if (update.status == UpdateStatus.downloading)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(value: update.progress, minHeight: 4),
                      ),
                    if (actions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
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

class _BannerButton extends StatefulWidget {
  final String label;
  final Color accent;
  final bool primary;
  final bool autofocus;
  final VoidCallback onPressed;

  const _BannerButton({
    required this.label,
    required this.accent,
    required this.onPressed,
    this.primary = false,
    this.autofocus = false,
  });

  @override
  State<_BannerButton> createState() => _BannerButtonState();
}

class _BannerButtonState extends State<_BannerButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            decoration: BoxDecoration(
              color: widget.primary ? widget.accent.withOpacity(_focused ? 0.95 : 0.6) : Colors.white.withOpacity(_focused ? 0.2 : 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _focused ? Colors.white : Colors.white24, width: 2),
              boxShadow: _focused ? [BoxShadow(color: widget.accent.withOpacity(0.55), blurRadius: 12)] : const [],
            ),
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

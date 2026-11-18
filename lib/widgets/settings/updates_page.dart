/*
 * Updates: check the project's GitHub releases and install a newer version.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/update_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class UpdatesPage extends StatelessWidget {
  static const String routeName = "updates_panel";

  /// For tests; the app creates the real service.
  final UpdateService? service;

  const UpdatesPage({super.key, this.service});

  @override
  Widget build(BuildContext context) {
    if (service != null) {
      return ChangeNotifierProvider<UpdateService>.value(value: service!, child: const _UpdatesBody());
    }
    // The app-wide service, so the banner and this page always show the same state.
    return const _UpdatesBody();
  }
}

class _UpdatesBody extends StatelessWidget {
  const _UpdatesBody();

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final update = context.watch<UpdateService>();
    final busy = update.status == UpdateStatus.checking ||
        update.status == UpdateStatus.downloading ||
        update.status == UpdateStatus.installing;

    String message;
    switch (update.status) {
      case UpdateStatus.idle:
        message = localizations.updatesHint;
        break;
      case UpdateStatus.checking:
        message = localizations.updatesChecking;
        break;
      case UpdateStatus.upToDate:
        message = localizations.updatesUpToDate;
        break;
      case UpdateStatus.available:
        message = "${localizations.updatesAvailable}: ${update.latest?.version ?? ''}";
        break;
      case UpdateStatus.downloading:
        message = "${localizations.updatesDownloading} ${(update.progress * 100).round()}%";
        break;
      case UpdateStatus.installing:
        message = localizations.updatesInstalling;
        break;
      case UpdateStatus.installed:
        message = localizations.updatesInstalled;
        break;
      case UpdateStatus.error:
        message = "${localizations.updatesFailed}: ${update.error ?? ''}";
        break;
    }

    return Column(
      children: [
        Text(localizations.updates, style: textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FocusableSettingsTile(
                  autofocus: true,
                  leading: busy
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.system_update),
                  title: Text(localizations.updatesCheck, style: textTheme.bodyMedium),
                  onPressed: busy ? null : () => update.check(),
                ),
                if (update.settings != null)
                  AnimatedBuilder(
                    animation: update.settings!,
                    builder: (_, __) => RoundedSwitchListTile(
                      secondary: const Icon(Icons.campaign_outlined),
                      title: Text(localizations.updatesShowBanner, style: textTheme.bodyMedium),
                      value: update.settings!.updateChecksEnabled,
                      onChanged: (value) async {
                        await update.settings!.setUpdateChecksEnabled(value);
                        // Switching it on again brings back a version that was ignored.
                        if (value) await update.settings!.setIgnoredUpdateVersion(null);
                      },
                    ),
                  ),
                if (update.status == UpdateStatus.available)
                  FocusableSettingsTile(
                    leading: const Icon(Icons.download),
                    title: Text(localizations.updatesInstall, style: textTheme.bodyMedium),
                    onPressed: () => update.downloadAndInstall(),
                  ),
                if (update.status == UpdateStatus.downloading)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: LinearProgressIndicator(value: update.progress),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(
                    message,
                    style: textTheme.bodySmall?.copyWith(
                      color: update.status == UpdateStatus.error ? Colors.redAccent : null,
                    ),
                  ),
                ),
                if (update.installedVersion.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    child: Text("${localizations.updatesInstalledVersion}: ${update.installedVersion}", style: textTheme.bodySmall),
                  ),
                if (update.status == UpdateStatus.available && (update.latest?.notes.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text(update.latest!.notes, style: textTheme.bodySmall, maxLines: 12, overflow: TextOverflow.ellipsis),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(localizations.updatesAdbHint, style: textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

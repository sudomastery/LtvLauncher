/*
 * Optimizations: switches that free memory on low-RAM TVs.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';

class OptimizationsPage extends StatefulWidget {
  static const String routeName = "optimizations_panel";

  /// The only app this page switches. SelfAdb.java enforces the same list on the Android side.
  static const String playStorePackage = "com.android.vending";

  final FLauncherChannel? channel;

  const OptimizationsPage({super.key, this.channel});

  @override
  State<OptimizationsPage> createState() => _OptimizationsPageState();
}

class _OptimizationsPageState extends State<OptimizationsPage> {
  late final FLauncherChannel _channel = widget.channel ?? FLauncherChannel();
  bool? _playStoreEnabled;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await _channel.isPackageEnabled(OptimizationsPage.playStorePackage);
    if (mounted) setState(() => _playStoreEnabled = enabled);
  }

  Future<void> _setPlayStoreDisabled(bool disabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final result = await _channel
          .setPackageEnabled(OptimizationsPage.playStorePackage, !disabled)
          .timeout(const Duration(seconds: 90));
      if (result['ok'] != true) {
        error = (result['message'] as String?)?.trim();
        if (error == null || error.isEmpty) error = "Unknown error";
      }
    } catch (e) {
      error = e.toString();
    }
    await _refresh();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final enabled = _playStoreEnabled;

    return Column(
      children: [
        Text(localizations.optimizations, style: textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RoundedSwitchListTile(
                  autofocus: true,
                  secondary: _busy
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.shop_outlined),
                  title: Text(localizations.optimizationsPlayStore, style: textTheme.bodyMedium),
                  value: enabled == false,
                  onChanged: (_busy || enabled == null) ? (_) {} : (value) => _setPlayStoreDisabled(value),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: Text(
                    _busy ? localizations.optimizationsWorking : localizations.optimizationsPlayStoreHint,
                    style: textTheme.bodySmall,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text(
                      "${localizations.optimizationsFailed}: $_error",
                      style: textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(localizations.optimizationsAdbHint, style: textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

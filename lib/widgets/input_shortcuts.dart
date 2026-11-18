/*
 * Small HDMI input shortcuts shown under the settings icons.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'package:flauncher/actions.dart';
import 'package:flauncher/models/tv_input.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/tv_inputs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// A row of small rounded chips, one per HDMI input. Pressing one switches the TV to that input.
class InputShortcuts extends StatelessWidget {
  const InputShortcuts({super.key});

  @override
  Widget build(BuildContext context) {
    final show = context.select<SettingsService, bool>((s) => s.showInputShortcuts);
    if (!show) return const SizedBox.shrink();

    final inputs = context
        .select<TvInputsService, List<TvInput>>((s) => s.inputs)
        .where((input) => input.type == TvInputType.hdmi)
        .toList();
    if (inputs.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, top: 2, bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final input in inputs)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _InputChip(input: input),
              ),
          ],
        ),
      ),
    );
  }
}

class _InputChip extends StatefulWidget {
  final TvInput input;

  const _InputChip({required this.input});

  @override
  State<_InputChip> createState() => _InputChipState();
}

class _InputChipState extends State<_InputChip> {
  bool _focused = false;

  /// "HDMI 1" -> "1"; custom names such as "Xbox" are kept short.
  String get _shortLabel {
    final label = widget.input.label.trim();
    final digits = RegExp(r'\d+').firstMatch(label)?.group(0);
    if (digits != null) return digits;
    return label.length > 6 ? label.substring(0, 6) : label;
  }

  void _open() => context.read<TvInputsService>().switchInput(widget.input.id);

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _open()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => _open()),
      },
      child: Focus(
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        onKeyEvent: (node, event) {
          // The settings icons live in the app bar above; Up goes straight to them.
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
            Actions.maybeInvoke(context, const MoveFocusToSettingsIntent());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: _open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _focused ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _focused ? accent : Colors.white.withOpacity(0.12), width: 2),
              boxShadow: _focused
                  ? [BoxShadow(color: accent.withOpacity(0.55), blurRadius: 14, spreadRadius: 1)]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_input_hdmi, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  _shortLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        shadows: const [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 4)],
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

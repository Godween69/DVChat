// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: скрытое меню разработчика. Открывается 20 быстрыми нажатиями (за 10 секунд)
// на заголовок «DVChat» в списке чатов. Ничего не подсвечивается: случайно не найти.

import 'dart:async';

import 'package:dvchat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

abstract class DvDevMenu {
  static const int _tapsNeeded = 20;
  static const Duration _window = Duration(seconds: 10);

  /// Показывать график нагрузки (кадры сборки и отрисовки); сбрасывается при перезапуске
  static final ValueNotifier<bool> perfOverlay = ValueNotifier(false);

  static final List<DateTime> _taps = [];

  /// Вызывается при каждом нажатии на заголовок
  static void tap(BuildContext context) {
    if (!PlatformInfos.isAndroid) return;
    final now = DateTime.now();
    _taps
      ..add(now)
      ..removeWhere((t) => now.difference(t) > _window);
    if (_taps.length < _tapsNeeded) return;
    _taps.clear();
    unawaited(HapticFeedback.heavyImpact());
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => const _DevSheet(),
      ),
    );
  }
}

class _DevSheet extends StatelessWidget {
  const _DevSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rate = View.of(context).display.refreshRate;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Меню разработчика',
              style: theme.textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.speed_outlined),
            title: const Text('Частота экрана'),
            subtitle: const Text(
              'Столько кадров в секунду система даёт приложению',
            ),
            trailing: Text(
              '${rate.round()} Гц',
              style: theme.textTheme.titleMedium,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: DvDevMenu.perfOverlay,
            builder: (context, on, _) => SwitchListTile(
              secondary: const Icon(Icons.insights_outlined),
              title: const Text('Показывать нагрузку'),
              subtitle: const Text(
                'Два графика вверху экрана: сборка кадров и отрисовка. Сбрасывается при перезапуске',
              ),
              value: on,
              onChanged: (value) => DvDevMenu.perfOverlay.value = value,
            ),
          ),
        ],
      ),
    );
  }
}

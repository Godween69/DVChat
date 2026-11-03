// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран «Оформление» (внешний вид): тема, цвета, шрифт, фон чата.

import 'package:dvchat/widgets/dv_blur_bar.dart';
import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/config/themes.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/chat/events/state_message.dart';
import 'package:dvchat/utils/account_config.dart';
import 'package:dvchat/utils/color_value.dart';
import 'package:dvchat/utils/dv_list_style.dart';
import 'package:dvchat/utils/dv_wallpaper_presets.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:dvchat/widgets/dv_list_card.dart';
import 'package:dvchat/widgets/layouts/max_width_body.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:dvchat/widgets/mxc_image.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/app_config.dart';
import 'settings_style.dart';

class SettingsStyleView extends StatelessWidget {
  final SettingsStyleController controller;

  const SettingsStyleView(this.controller, {super.key});

  /// Пример строки списка. Не const, чтобы перерисовывался при смене оформления.
  Widget _sampleCard(String letter, String name, String text) => DvListCard(
    child: ListTile(
      leading: CircleAvatar(child: Text(letter)),
      title: Text(name),
      subtitle: Text(text),
    ),
  );

  /// Миниатюра стиля списка: две строки в этом стиле и подпись; выбранная обведена
  Widget _styleChip(BuildContext context, String mode, String label) {
    final theme = Theme.of(context);
    final selected = DvListStyle.mode == mode;
    final on = theme.colorScheme.onSurface;
    Widget miniRow() => Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: mode == DvListStyle.plates ? on.withAlpha(30) : null,
        borderRadius: BorderRadius.circular(8),
        border: mode == DvListStyle.frames
            ? Border.all(color: on.withAlpha(100))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withAlpha(140),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 4,
                  width: 34,
                  decoration: BoxDecoration(
                    color: on.withAlpha(160),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: on.withAlpha(70),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => controller.setListStyle(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected
                  ? theme.colorScheme.primary.withAlpha(24)
                  : null,
              border: Border.all(
                color: selected ? theme.colorScheme.primary : theme.dividerColor,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                miniRow(),
                miniRow(),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Круглый цветной значок темы; выбранный обведён
  Widget _themeChip(ThemeMode mode, IconData icon, Color color, String label) {
    final selected = controller.currentTheme == mode;
    return Expanded(
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => controller.switchTheme(mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withAlpha(selected ? 70 : 30),
                  border: Border.all(
                    color: selected ? color : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ряд готовых обоев: первый кружок «без обоев»
  Widget _presetRow(BuildContext context) {
    final theme = Theme.of(context);
    final current = AppSettings.chatWallpaperPreset.value;
    Widget swatch(String id, Widget? inner, Gradient? g, String label) {
      final selected = current == id;
      return Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: () => controller.setWallpaperPreset(id),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: g,
              color: g == null ? theme.colorScheme.surfaceContainerHighest : null,
              border: Border.all(
                color: selected ? theme.colorScheme.primary : theme.dividerColor,
                width: selected ? 3 : 1,
              ),
            ),
            child: inner,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          swatch('', const Icon(Icons.block, size: 20), null, 'Без обоев'),
          for (final p in DvWallpapers.all) swatch(p.id, null, p.swatch, p.name),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const colorPickerSize = 32.0;
    final client = Matrix.of(context).client;
    return Scaffold(extendBodyBehindAppBar: true, 
      appBar: AppBar(flexibleSpace: const DvBlurBar(), 
        automaticallyImplyLeading: !DvThemes.isColumnMode(context),
        centerTitle: DvThemes.isColumnMode(context),
        title: Text(L10n.of(context).changeTheme),
      ),
      backgroundColor: theme.colorScheme.surface,
      body: MaxWidthBody(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              // DVChat: тема выбирается цветными значками (солнце, луна, авто)
              child: Row(
                children: [
                  _themeChip(ThemeMode.light, Icons.light_mode, Colors.amber.shade700, L10n.of(context).lightTheme),
                  _themeChip(ThemeMode.dark, Icons.dark_mode, Colors.indigo.shade400, L10n.of(context).darkTheme),
                  _themeChip(ThemeMode.system, Icons.brightness_auto, Colors.teal, L10n.of(context).systemTheme),
                ],
              ),
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                'Шапка',
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'Верхняя полоса экранов. Слева прозрачное стекло, справа сплошной цвет: так шапка не сливается с сообщениями',
              ),
              trailing: Text('${(DvBlurBar.opacity * 100).round()}%'),
            ),
            const _HeaderSample(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Slider(
                value: DvBlurBar.opacity,
                onChanged: controller.previewHeaderOpacity,
                onChangeEnd: controller.saveHeaderOpacity,
              ),
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                'Оформление списков',
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text('Как выглядят чаты, друзья и архив'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  _styleChip(context, DvListStyle.plain, 'Обычный'),
                  _styleChip(context, DvListStyle.plates, 'Плашки'),
                  _styleChip(context, DvListStyle.frames, 'Рамки'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _sampleCard('Д', 'Дмитрий', 'Так выглядит список'),
            _sampleCard('С', 'Степан', 'Чаты и друзья оформляются одинаково'),
            if (!DvListStyle.isPlain) ...[
              const ListTile(
                title: Text('Контраст'),
                subtitle: Text(
                  'Насколько плашки и рамки отличаются от фона: слева почти сливаются, справа заметнее',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Slider(
                  value: DvListStyle.contrast,
                  onChanged: controller.previewListContrast,
                  onChangeEnd: controller.saveListContrast,
                ),
              ),
            ],
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).setColorTheme,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            DynamicColorBuilder(
              builder: (light, dark) {
                final systemColor =
                    Theme.of(context).brightness == Brightness.light
                    ? light?.primary
                    : dark?.primary;
                final colors = [null, AppConfig.chatColor, ..._dvSeeds];
                if (systemColor == null) {
                  colors.remove(null);
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 64,
                  ),
                  itemCount: colors.length,
                  itemBuilder: (context, i) {
                    final color = colors[i];
                    // Показываем цвет, который реально получится у сообщений в этой теме
                    final seed = color ?? systemColor;
                    final isDark = theme.brightness == Brightness.dark;
                    final scheme = seed == null
                        ? null
                        : ColorScheme.fromSeed(
                            seedColor: seed,
                            brightness: theme.brightness,
                            dynamicSchemeVariant: DynamicSchemeVariant.rainbow,
                          );
                    final swatch = scheme == null
                        ? null
                        : (isDark ? scheme.primaryContainer : scheme.primary);
                    final onSwatch = scheme == null
                        ? null
                        : (isDark
                              ? scheme.onPrimaryContainer
                              : scheme.onPrimary);
                    return Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Tooltip(
                        message: color == null
                            ? L10n.of(context).systemTheme
                            : '#${color.hexValue.toRadixString(16).toUpperCase()}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(colorPickerSize),
                          onTap: () => controller.setChatColor(color),
                          child: Material(
                            color: swatch,
                            elevation: 6,
                            borderRadius: BorderRadius.circular(
                              colorPickerSize,
                            ),
                            child: SizedBox(
                              width: colorPickerSize,
                              height: colorPickerSize,
                              child:
                                  controller.currentColor?.toARGB32() ==
                                      color?.toARGB32()
                                  ? Center(
                                      child: Icon(
                                        Icons.check,
                                        size: 16,
                                        color: onSwatch,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              title: Text(
                L10n.of(context).messagesStyle,
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            StreamBuilder(
              stream: client.onSync.stream.where(
                (syncUpdate) =>
                    syncUpdate.accountData?.any(
                      (accountData) =>
                          accountData.type ==
                          ApplicationAccountConfigExtension.accountDataKey,
                    ) ??
                    false,
              ),
              builder: (context, snapshot) {
                final accountConfig = client.applicationAccountConfig;

                return Column(
                  mainAxisSize: .min,
                  children: [
                    MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(
                          AppSettings.fontSizeFactor.value,
                        ),
                      ),
                      child: AnimatedContainer(
                        duration: DvThemes.animationDuration,
                        curve: DvThemes.animationCurve,
                        // Обрезка по краям требует decoration; без неё в готовой сборке
                        // ошибка и вместо блока бесконечная белая пустота
                        decoration: const BoxDecoration(),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (accountConfig.wallpaperUrl == null &&
                                DvWallpapers.byId(
                                      AppSettings.chatWallpaperPreset.value,
                                    ) !=
                                    null)
                              // Те же обои и тот же рисунок, что будут в ленте чата
                              Positioned.fill(
                                child: DvWallpaperLayer(
                                  preset: DvWallpapers.byId(
                                    AppSettings.chatWallpaperPreset.value,
                                  )!,
                                  dark: theme.brightness == Brightness.dark,
                                ),
                              ),
                            if (accountConfig.wallpaperUrl != null)
                              Stack(
                                children: [
                                  MxcImage(
                                    key: ValueKey(accountConfig.wallpaperUrl),
                                    uri: accountConfig.wallpaperUrl,
                                    fit: BoxFit.cover,
                                    isThumbnail: true,
                                    width: DvThemes.columnWidth * 2,
                                    height: 212,
                                  ),
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: theme.colorScheme.surface
                                          .withAlpha(
                                            (255 *
                                                    (1 -
                                                        controller
                                                            .wallpaperOpacity
                                                            .clamp(0.0, 1.0)))
                                                .round(),
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            Column(
                              mainAxisSize: .min,
                              children: [
                                const SizedBox(height: 16),
                                StateMessage(
                                  Event(
                                    eventId: 'style_dummy',
                                    room: Room(
                                      id: '!style_dummy',
                                      client: client,
                                    ),
                                    content: {'membership': 'join'},
                                    type: EventTypes.RoomMember,
                                    senderId: client.userID!,
                                    originServerTs: DateTime.now(),
                                    stateKey: client.userID,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.only(
                                    left: 12 + 12 + Avatar.defaultSize,
                                    right: 12,
                                    top: (accountConfig.wallpaperUrl == null &&
                                            AppSettings.chatWallpaperPreset.value.isEmpty)
                                        ? 0
                                        : 12,
                                    bottom: 12,
                                  ),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: theme.bubbleColor,
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        'Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor',
                                        style: TextStyle(
                                          color: theme.onBubbleColor,
                                          fontSize: AppConfig.messageFontSize,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: 12,
                                      left: 12,
                                      top: (accountConfig.wallpaperUrl == null &&
                                              AppSettings.chatWallpaperPreset.value.isEmpty)
                                          ? 0
                                          : 12,
                                      bottom: 12,
                                    ),
                                    child: Material(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(
                                        AppConfig.borderRadius,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          'Lorem ipsum dolor sit amet',
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface,
                                            fontSize: AppConfig.messageFontSize,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Divider(color: theme.dividerColor),
                    ListTile(
                      title: Text(
                        'Готовые обои',
                        style: TextStyle(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text('Свою картинку можно поставить ниже, она важнее'),
                    ),
                    _presetRow(context),
                    Divider(color: theme.dividerColor),
                    ListTile(
                      title: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondaryContainer,
                          foregroundColor:
                              theme.colorScheme.onSecondaryContainer,
                        ),
                        onPressed: controller.setWallpaper,
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(L10n.of(context).setWallpaper),
                      ),
                      trailing: accountConfig.wallpaperUrl == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.delete_outlined),
                              color: theme.colorScheme.error,
                              onPressed: controller.deleteChatWallpaper,
                            ),
                    ),
                    if (accountConfig.wallpaperUrl != null) ...[
                      ListTile(title: Text(L10n.of(context).opacity)),
                      Slider.adaptive(
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        semanticFormatterCallback: (d) => d.toString(),
                        value: controller.wallpaperOpacity,
                        onChanged: controller.updateWallpaperOpacity,
                        onChangeEnd: controller.saveWallpaperOpacity,
                      ),
                    ],
                  ],
                );
              },
            ),
            ListTile(
              title: Text(L10n.of(context).fontSize),
              trailing: Text('× ${AppSettings.fontSizeFactor.value}'),
            ),
            Slider.adaptive(
              min: 0.5,
              max: 2.5,
              divisions: 20,
              value: AppSettings.fontSizeFactor.value,
              semanticFormatterCallback: (d) => d.toString(),
              onChanged: controller.changeFontSizeFactor,
            ),
          ],
        ),
      ),
    );
  }
}

/// DVChat: 19 заметно разных оттенков по кругу (красный, оранжевый, олива, зелёные,
/// бирюза, голубые, синие, фиолетовые, розовые)
final List<Color> _dvSeeds = [
  for (final h in const [
    0, 14, 28, 62, 90, 120, 145, 165, 180, 195,
    210, 225, 240, 258, 275, 292, 310, 328, 345, //
  ])
    HSLColor.fromAHSL(1, h.toDouble(), 0.78, 0.5).toColor(),
];

/// DVChat: образец шапки над несколькими строками текста: видно, как она ляжет на сообщения
class _HeaderSample extends StatelessWidget {
  const _HeaderSample();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 96,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in const [
                        'Купил молоко и хлеб, заеду через час',
                        'Хорошо, не забудь яйца',
                        'Уже в магазине, беру десяток',
                        'Спасибо, жду дома',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(line, style: theme.textTheme.bodyMedium),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 40,
                child: Stack(
                  children: [
                    const Positioned.fill(child: DvBlurBar()),
                    Center(
                      child: Text(
                        'Так выглядит шапка',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

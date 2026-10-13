// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/config/themes.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/chat/events/state_message.dart';
import 'package:dvchat/utils/account_config.dart';
import 'package:dvchat/utils/color_value.dart';
import 'package:dvchat/widgets/avatar.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const colorPickerSize = 32.0;
    final client = Matrix.of(context).client;
    return Scaffold(
      appBar: AppBar(
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
              child: SegmentedButton<ThemeMode>(
                selected: {controller.currentTheme},
                onSelectionChanged: (selected) =>
                    controller.switchTheme(selected.single),
                segments: [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(L10n.of(context).lightTheme),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(L10n.of(context).darkTheme),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(L10n.of(context).systemTheme),
                    icon: const Icon(Icons.auto_mode_outlined),
                  ),
                ],
              ),
            ),
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
                final colors = [null, AppConfig.chatColor, ...Colors.primaries];
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
                            color: color ?? systemColor,
                            elevation: 6,
                            borderRadius: BorderRadius.circular(
                              colorPickerSize,
                            ),
                            child: SizedBox(
                              width: colorPickerSize,
                              height: colorPickerSize,
                              child: controller.currentColor == color
                                  ? Center(
                                      child: Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
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
                'Цвет фона чата',
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in <int>[
                    0,
                    0xFFFFD6D6,
                    0xFFFFE0B8,
                    0xFFFFF1A8,
                    0xFFC8EBBB,
                    0xFFB5E6DC,
                    0xFFB7D6FF,
                    0xFFD3C2FF,
                    0xFF7A2E3E,
                    0xFF2F6B4F,
                    0xFF1F3F7A,
                    0xFF4A2F7A,
                  ])
                    InkWell(
                      borderRadius: BorderRadius.circular(colorPickerSize),
                      onTap: () => controller.setChatBackground(c),
                      child: Container(
                        width: colorPickerSize,
                        height: colorPickerSize,
                        decoration: BoxDecoration(
                          color: c == 0 ? theme.colorScheme.surface : Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppSettings.chatBackgroundColorInt.value == c
                                ? theme.colorScheme.primary
                                : theme.dividerColor,
                            width: AppSettings.chatBackgroundColorInt.value == c
                                ? 3
                                : 1,
                          ),
                        ),
                        child: c == 0
                            ? Icon(
                                Icons.format_color_reset_outlined,
                                size: 16,
                                color: theme.colorScheme.onSurface,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
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
                        decoration: BoxDecoration(
                          color: AppSettings.chatBackgroundColorInt.value == 0
                              ? null
                              : Color(AppSettings.chatBackgroundColorInt.value),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (accountConfig.wallpaperUrl != null)
                              Opacity(
                                opacity: controller.wallpaperOpacity,
                                child: ImageFiltered(
                                  imageFilter: ImageFilter.blur(
                                    sigmaX: controller.wallpaperBlur,
                                    sigmaY: controller.wallpaperBlur,
                                  ),
                                  child: MxcImage(
                                    key: ValueKey(accountConfig.wallpaperUrl),
                                    uri: accountConfig.wallpaperUrl,
                                    fit: BoxFit.cover,
                                    isThumbnail: true,
                                    width: DvThemes.columnWidth * 2,
                                    height: 212,
                                  ),
                                ),
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
                                    top: accountConfig.wallpaperUrl == null
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
                                      top: accountConfig.wallpaperUrl == null
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
                      ListTile(title: Text(L10n.of(context).blur)),
                      Slider.adaptive(
                        min: 0.0,
                        max: 10.0,
                        divisions: 10,
                        semanticFormatterCallback: (d) => d.toString(),
                        value: controller.wallpaperBlur,
                        onChanged: controller.updateWallpaperBlur,
                        onChangeEnd: controller.saveWallpaperBlur,
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

// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран «Оформление» (логика): тема, цвета, шрифт, фон чата.

import 'dart:math';

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/utils/account_config.dart';
import 'package:dvchat/utils/dv_list_style.dart';
import 'package:dvchat/utils/dv_wallpaper.dart';
import 'package:dvchat/utils/file_selector.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
import 'package:dvchat/widgets/theme_builder.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';
import 'settings_style_view.dart';

class SettingsStyle extends StatefulWidget {
  const SettingsStyle({super.key});

  @override
  SettingsStyleController createState() => SettingsStyleController();
}

class SettingsStyleController extends State<SettingsStyle> {
  void setChatColor(Color? color) {
    AppSettings.colorSchemeSeedInt.setItem(
      color?.toARGB32() ?? AppSettings.colorSchemeSeedInt.defaultValue,
    );
    ThemeController.of(context).setPrimaryColor(color);
  }

  Future<void> setListStyle(String style) async {
    await AppSettings.listStyle.setItem(style);
    DvListStyle.changed();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    DvListStyle.previewContrast = null;
    super.dispose();
  }

  // Ползунок контраста: пока тянем, показываем сразу, сохраняем в конце
  void previewListContrast(double value) {
    DvListStyle.previewContrast = value;
    DvListStyle.changed();
    setState(() {});
  }

  Future<void> saveListContrast(double value) async {
    await AppSettings.listContrast.setItem(value);
    DvListStyle.previewContrast = null;
    DvListStyle.changed();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> setWallpaper() async {
    final client = Matrix.of(context).client;
    final picked = await selectFiles(context, type: FileType.image);
    final pickedFile = picked.firstOrNull;
    if (pickedFile == null) return;
    if (!mounted) return;

    // DVChat: подгоняем фото под экран (масштаб + обрезка по центру, JPEG): такие обои
    // почти ничего не стоят при отрисовке ленты и быстро грузятся
    final screen =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    final longSide = max(screen.width, screen.height).round();
    final shortSide = min(screen.width, screen.height).round();
    await showFutureLoadingDialog(
      context: context,
      title: 'Оптимизация обоев под экран…',
      future: () async {
        final original = await pickedFile.readAsBytes();
        var bytes = original;
        var name = pickedFile.name;
        String? mimeType;
        final fitted = await DvWallpaper.fitToScreen(
          original,
          width: shortSide,
          height: longSide,
        );
        if (fitted != null) {
          bytes = fitted;
          name = 'wallpaper.jpg';
          mimeType = 'image/jpeg';
        } else {
          // Фото меньше экрана или не вышло: обычное сжатие (длинная сторона до 2000 точек)
          final image = await MatrixImageFile.shrink(
            bytes: original,
            name: pickedFile.name,
            maxDimension: 2000,
            customImageResizer: client.customImageResizer,
          );
          bytes = image.bytes;
          name = image.name;
          mimeType = image.mimeType;
        }
        final url = await client.uploadContent(
          bytes,
          filename: name,
          contentType: mimeType,
        );
        await client.updateApplicationAccountConfig(
          ApplicationAccountConfig(wallpaperUrl: url),
        );
      },
    );
  }

  double get wallpaperOpacity =>
      _wallpaperOpacity ??
      Matrix.of(context).client.applicationAccountConfig.wallpaperOpacity ??
      0.5;

  double? _wallpaperOpacity;

  Future<void> saveWallpaperOpacity(double opacity) async {
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.updateApplicationAccountConfig(
        ApplicationAccountConfig(wallpaperOpacity: opacity),
      ),
    );
    if (result.isValue) return;

    setState(() {
      _wallpaperOpacity = client.applicationAccountConfig.wallpaperOpacity;
    });
  }

  void updateWallpaperOpacity(double opacity) {
    setState(() {
      _wallpaperOpacity = opacity;
    });
  }

  void deleteChatWallpaper() => showFutureLoadingDialog(
    context: context,
    future: () => Matrix.of(context).client.setApplicationAccountConfig(
      const ApplicationAccountConfig(wallpaperUrl: null, wallpaperBlur: null),
    ),
  );

  // DVChat: выбор цвета фона чата
  Future<void> setChatBackground(int value) async {
    await AppSettings.chatBackgroundColorInt.setItem(value);
    setState(() {});
  }

  ThemeMode get currentTheme => ThemeController.of(context).themeMode;
  Color? get currentColor => ThemeController.of(context).primaryColor;

  void switchTheme(ThemeMode? newTheme) {
    if (newTheme == null) return;
    switch (newTheme) {
      case ThemeMode.light:
        ThemeController.of(context).setThemeMode(ThemeMode.light);
        break;
      case ThemeMode.dark:
        ThemeController.of(context).setThemeMode(ThemeMode.dark);
        break;
      case ThemeMode.system:
        ThemeController.of(context).setThemeMode(ThemeMode.system);
        break;
    }
    setState(() {});
  }

  Future<void> changeFontSizeFactor(double d) async {
    await AppSettings.fontSizeFactor.setItem(d);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsStyleView(this);
}

// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: экран приветствия для не вошедшего пользователя.
//
// Вход в DVChat только по приглашению от администратора: либо сканированием
// QR-кода, либо вставкой ссылки из буфера обмена. Логики входа здесь нет,
// она в utils/sign_in_flows/link_login.dart.

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:dvchat/utils/sign_in_flows/link_login.dart';
import 'package:dvchat/widgets/dv_install_hint.dart';
import 'package:dvchat/widgets/dv_logo.dart';
import 'package:dvchat/widgets/layouts/login_scaffold.dart';
import 'package:material_ui/material_ui.dart';

class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showLoggedOutNotice());
  }

  /// После выхода из аккаунта объясняем, как вернуться (окно закрывается только кнопкой)
  Future<void> _showLoggedOutNotice() async {
    if (!mounted || !AppSettings.loggedOutNoticePending.value) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Вы вышли из аккаунта'),
          content: const Text(
            'Чтобы снова войти, обратитесь к администратору: он выдаст новую ссылку или QR-код. '
            'Другим способом войти в свой аккаунт не получится.\n\n'
            'Администратору понадобится ваш уникальный ID аккаунта (10 цифр), '
            'без него вход не выполнить.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Понятно'),
            ),
          ],
        ),
      ),
    );
    await AppSettings.loggedOutNoticePending.setItem(false);
  }

  @override
  Widget build(BuildContext context) {
    return LoginScaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(AppSettings.applicationName.value),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(32.0),
                      child: const DvLogo(size: 128),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Приветствую вас в семейном мессенджере',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (DvInstallHint.needed) const DvInstallHint(),
                          // Вход по QR-коду от администратора (нужна камера, в вебе её нет)
                          if (!PlatformInfos.isWeb)
                            TextButton.icon(
                              onPressed: () => scanAndLogin(context),
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Сканировать QR'),
                            ),
                          // Вход по ссылке из буфера обмена
                          TextButton.icon(
                            onPressed: () => pasteAndLogin(context),
                            icon: const Icon(Icons.content_paste_outlined),
                            label: const Text('Вставить ссылку'),
                          ),
                          // Веб-версия: ссылку можно вставить в поле вручную
                          if (PlatformInfos.isWeb)
                            TextButton.icon(
                              onPressed: () => typeLinkAndLogin(context),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Ввести ссылку вручную'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

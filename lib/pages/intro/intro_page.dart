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
import 'package:dvchat/utils/sign_in_flows/link_login.dart';
import 'package:dvchat/widgets/dv_logo.dart';
import 'package:dvchat/widgets/layouts/login_scaffold.dart';
import 'package:material_ui/material_ui.dart';

class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

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
                          // Вход по QR-коду от администратора
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

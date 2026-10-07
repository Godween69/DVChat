// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/sign_in_flows/link_login.dart';
import 'package:fluffychat/widgets/layouts/login_scaffold.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

class IntroPage extends StatelessWidget {
  // Сигнатуру не меняем, чтобы не трогать intro_page_presenter.dart
  final bool isLoading, hasPresetHomeserver;
  final String? loggingInToHomeserver, welcomeText;
  final VoidCallback login;

  const IntroPage({
    required this.isLoading,
    required this.loggingInToHomeserver,
    super.key,
    required this.hasPresetHomeserver,
    required this.welcomeText,
    required this.login,
  });

  @override
  Widget build(BuildContext context) {
    final addMultiAccount = Matrix.of(
      context,
    ).widget.clients.any((client) => client.isLogged());
    final loggingInToHomeserver = this.loggingInToHomeserver;

    return LoginScaffold(
      appBar: AppBar(
        centerTitle: true,
        title: addMultiAccount
            ? Text(L10n.of(context).addAccount)
            : Text(AppSettings.applicationName.value),
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator.adaptive(),
                  if (loggingInToHomeserver != null)
                    Text(L10n.of(context).logInTo(loggingInToHomeserver)),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(32.0),
                            child: Hero(
                              tag: 'info-logo',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(128),
                                child: Image.asset(
                                  './assets/logo/mini/logo_mini.png',
                                  width: 128,
                                  height: 128,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            AppSettings.applicationName.value,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 28),
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Обычный вход: форма логин/пароль
                                ElevatedButton(
                                  onPressed: login,
                                  child: Text(L10n.of(context).signIn),
                                ),
                                const SizedBox(height: 8),
                                // Вход по ссылке из буфера обмена
                                TextButton.icon(
                                  onPressed: () => pasteAndLogin(context),
                                  icon: const Icon(
                                    Icons.content_paste_outlined,
                                  ),
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

// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/sign_in_flows/link_login.dart';
import 'package:fluffychat/widgets/dv_logo.dart';
import 'package:fluffychat/widgets/layouts/login_scaffold.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

class IntroPage extends StatelessWidget {
  // Сигнатуру пока не меняем, чтобы не трогать intro_page_presenter.dart
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

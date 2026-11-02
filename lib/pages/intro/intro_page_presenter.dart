// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: обёртка экрана приветствия.
//
// Следит за ссылкой входа, которую присылает система (Android App Link /
// схема ссылок). Если ссылка пришла, пока открыт экран приветствия, или
// была получена при холодном старте, сразу запускает вход по ней.

import 'package:dvchat/pages/intro/intro_page.dart';
import 'package:dvchat/utils/sign_in_flows/link_login.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

class IntroPagePresenter extends StatefulWidget {
  const IntroPagePresenter({super.key});

  @override
  State<IntroPagePresenter> createState() => _IntroPagePresenterState();
}

class _IntroPagePresenterState extends State<IntroPagePresenter> {
  @override
  void initState() {
    super.initState();
    // Слушатель ловит ссылку при открытом приложении, проверка после
    // первого кадра ловит холодный старт.
    PendingLoginLink.notifier.addListener(_onPendingLink);
    SchedulerBinding.instance.addPostFrameCallback((_) => _onPendingLink());
  }

  @override
  void dispose() {
    PendingLoginLink.notifier.removeListener(_onPendingLink);
    super.dispose();
  }

  void _onPendingLink() {
    if (!mounted) return;
    final link = PendingLoginLink.take();
    if (link != null) loginByLink(context, link);
  }

  @override
  Widget build(BuildContext context) => const IntroPage();
}

// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: обёртка строки списка: в режимах «плашки» и «рамки» рисует карточку, в обычном ничего не меняет.

import 'package:dvchat/utils/dv_list_style.dart';
import 'package:material_ui/material_ui.dart';

class DvListCard extends StatelessWidget {
  const DvListCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (DvListStyle.isPlain) return child;
    return Padding(
      padding: DvListStyle.outerPadding,
      child: Material(
        shape: DvListStyle.shape(context),
        clipBehavior: Clip.hardEdge,
        color: DvListStyle.fill(context),
        elevation: DvListStyle.elevation,
        shadowColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        child: child,
      ),
    );
  }
}

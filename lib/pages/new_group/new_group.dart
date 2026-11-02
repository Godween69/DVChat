// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: создание группового чата.
//
// Контроллер экрана «Новая группа»: имя, аватар, публичность. После создания
// открывает экран приглашения участников.

import 'dart:typed_data';

import 'package:dvchat/pages/new_group/new_group_view.dart';
import 'package:dvchat/utils/file_selector.dart';
import 'package:dvchat/widgets/avatar_crop_dialog.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' as sdk;

class NewGroup extends StatefulWidget {
  const NewGroup({super.key});

  @override
  NewGroupController createState() => NewGroupController();
}

class NewGroupController extends State<NewGroup> {
  TextEditingController nameController = TextEditingController();

  bool publicGroup = false;
  bool groupCanBeFound = false;

  Uint8List? avatar;

  Uri? avatarUrl;

  Object? error;

  bool loading = false;

  void setPublicGroup(bool b) =>
      setState(() => publicGroup = groupCanBeFound = b);

  void setGroupCanBeFound(bool b) => setState(() => groupCanBeFound = b);

  Future<void> selectPhoto() async {
    final photo = await selectFiles(
      context,
      type: FileType.image,
      allowMultiple: false,
    );
    var bytes = await photo.singleOrNull?.readAsBytes();
    // DVChat: обрезка аватара группы
    if (bytes != null) {
      if (!mounted) return;
      bytes = await cropAvatar(context, bytes);
      if (bytes == null) return;
    }

    setState(() {
      avatarUrl = null;
      avatar = bytes;
    });
  }

  Future<void> _createGroup() async {
    if (!mounted) return;
    final client = Matrix.of(context).client;

    final roomId = await client.createGroupChat(
      visibility: groupCanBeFound
          ? sdk.Visibility.public
          : sdk.Visibility.private,
      preset: publicGroup
          ? sdk.CreateRoomPreset.publicChat
          : sdk.CreateRoomPreset.privateChat,
      groupName: nameController.text.isNotEmpty ? nameController.text : null,
      initialState: [
        if (avatar != null)
          sdk.StateEvent(
            type: sdk.EventTypes.RoomAvatar,
            content: {'url': avatarUrl.toString()},
          ),
      ],
    );
    if (!mounted) return;

    context.go('/rooms/$roomId/invite');
  }

  Future<void> submitAction([_]) async {
    final client = Matrix.of(context).client;

    try {
      setState(() {
        loading = true;
        error = null;
      });

      final avatar = this.avatar;
      avatarUrl ??= avatar == null ? null : await client.uploadContent(avatar);

      if (!mounted) return;

      await _createGroup();
    } catch (e, s) {
      sdk.Logs().d('Unable to create group', e, s);
      setState(() {
        error = e;
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NewGroupView(this);
}

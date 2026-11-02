// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Нижняя строка ввода: поле, кнопки вложений, отправки и записи голоса.

import 'package:dvchat/config/setting_keys.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/chat/recording_input_row.dart';
import 'package:dvchat/pages/chat/recording_view_model.dart';
import 'package:dvchat/utils/other_party_can_receive.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:dvchat/widgets/dv_glass.dart';
import 'package:dvchat/widgets/hover_builder.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import 'chat.dart';
import 'input_bar.dart';

class ChatInputRow extends StatelessWidget {
  final ChatController controller;

  static const double height = 56.0;

  const ChatInputRow(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textMessageOnly =
        controller.sendController.text.isNotEmpty ||
        controller.replyEvent != null ||
        controller.editEvent != null;

    if (!controller.room.otherPartyCanReceiveMessages) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final selectedTextButtonStyle = TextButton.styleFrom(
      foregroundColor: theme.colorScheme.onTertiaryContainer,
    );

    return RecordingViewModel(
      builder: (context, recordingViewModel) {
        if (recordingViewModel.isRecording) {
          return RecordingInputRow(
            state: recordingViewModel,
            onSend: controller.onVoiceMessageSend,
          );
        }
        return Row(
          crossAxisAlignment: .end,
          mainAxisAlignment: .spaceBetween,
          children: controller.selectMode
              ? <Widget>[
                  if (controller.selectedEvents.every(
                    (event) => event.status == EventStatus.error,
                  ))
                    SizedBox(
                      height: height,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: controller.deleteErrorEventsAction,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.delete_forever_outlined),
                            Text(L10n.of(context).delete),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: height,
                      child: TextButton(
                        style: selectedTextButtonStyle,
                        onPressed: controller.forwardEventsAction,
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.keyboard_arrow_left_outlined),
                            Text(L10n.of(context).forward),
                          ],
                        ),
                      ),
                    ),
                  controller.selectedEvents.length == 1
                      ? controller.selectedEvents.first
                                .getDisplayEvent(controller.timeline!)
                                .status
                                .isSent
                            ? SizedBox(
                                height: height,
                                child: TextButton(
                                  style: selectedTextButtonStyle,
                                  onPressed: controller.replyAction,
                                  child: Row(
                                    children: <Widget>[
                                      Text(L10n.of(context).reply),
                                      const Icon(Icons.keyboard_arrow_right),
                                    ],
                                  ),
                                ),
                              )
                            : SizedBox(
                                height: height,
                                child: TextButton(
                                  style: selectedTextButtonStyle,
                                  onPressed: controller.sendAgainAction,
                                  child: Row(
                                    children: <Widget>[
                                      Text(L10n.of(context).tryToSendAgain),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.send_outlined, size: 16),
                                    ],
                                  ),
                                ),
                              )
                      : const SizedBox.shrink(),
                ]
              : <Widget>[
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: DvThemes.animationDuration,
                    curve: DvThemes.animationCurve,
                    width: textMessageOnly ? 0 : 48,
                    height: height,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(),
                    clipBehavior: Clip.hardEdge,
                    child: Builder(
                      builder: (anchor) => IconButton(
                        tooltip: 'Добавить',
                        icon: const Icon(Icons.add_circle_outline),
                        color: theme.colorScheme.onPrimaryContainer,
                        onPressed: () async {
                          final choice =
                              await showDvGlassMenu<AddPopupMenuActions>(
                                anchor,
                                place: DvGlassMenuPlace.aboveStart,
                                items: [
                                  if (PlatformInfos.isMobile)
                                    const DvGlassMenuItem(
                                      value: AddPopupMenuActions.location,
                                      icon: Icons.location_on_rounded,
                                      title: 'Геопозиция',
                                      color: DvMenuColors.red,
                                    ),
                                  const DvGlassMenuItem(
                                    value: AddPopupMenuActions.poll,
                                    icon: Icons.poll_rounded,
                                    title: 'Опрос',
                                    color: DvMenuColors.purple,
                                  ),
                                  const DvGlassMenuItem(
                                    value: AddPopupMenuActions.shopping,
                                    icon: Icons.shopping_cart_rounded,
                                    title: 'Список покупок',
                                    color: DvMenuColors.green,
                                  ),
                                  if (PlatformInfos.isMobile) ...[
                                    const DvGlassMenuItem(
                                      value: AddPopupMenuActions.videoCamera,
                                      icon: Icons.videocam_rounded,
                                      title: 'Записать видео',
                                      color: DvMenuColors.pink,
                                      dividerBefore: true,
                                    ),
                                    const DvGlassMenuItem(
                                      value: AddPopupMenuActions.photoCamera,
                                      icon: Icons.photo_camera_rounded,
                                      title: 'Сделать фото',
                                      color: DvMenuColors.orange,
                                    ),
                                  ],
                                  DvGlassMenuItem(
                                    value: AddPopupMenuActions.video,
                                    icon: Icons.movie_rounded,
                                    title: 'Видео',
                                    color: DvMenuColors.teal,
                                    dividerBefore: !PlatformInfos.isMobile,
                                  ),
                                  const DvGlassMenuItem(
                                    value: AddPopupMenuActions.image,
                                    icon: Icons.image_rounded,
                                    title: 'Фото',
                                    color: DvMenuColors.blue,
                                  ),
                                  const DvGlassMenuItem(
                                    value: AddPopupMenuActions.file,
                                    icon: Icons.attach_file_rounded,
                                    title: 'Файл',
                                    color: DvMenuColors.amber,
                                  ),
                                ],
                              );
                          if (choice == null || !anchor.mounted) return;
                          controller.onAddPopupMenuButtonSelected(choice);
                        },
                      ),
                    ),
                  ),
                  Container(
                    height: height,
                    width: 48,
                    alignment: Alignment.center,
                    child: IconButton(
                      tooltip: L10n.of(context).emojis,
                      color: theme.colorScheme.onPrimaryContainer,
                      icon: Icon(
                        controller.showEmojiPicker
                            ? Icons.keyboard
                            : Icons.add_reaction_outlined,
                        key: ValueKey(controller.showEmojiPicker),
                      ),
                      onPressed: controller.emojiPickerAction,
                    ),
                  ),
                  if (Matrix.of(context).isMultiAccount &&
                      Matrix.of(context).hasComplexBundles &&
                      Matrix.of(context).currentBundle!.length > 1)
                    Container(
                      height: height,
                      width: 48,
                      alignment: Alignment.center,
                      child: _ChatAccountPicker(controller),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: InputBar(
                        room: controller.room,
                        minLines: 1,
                        maxLines: 8,
                        autofocus: !PlatformInfos.isMobile,
                        keyboardType: TextInputType.multiline,
                        textInputAction:
                            AppSettings.sendOnEnter.value == true &&
                                PlatformInfos.isMobile
                            ? TextInputAction.send
                            : null,
                        onSubmitted: controller.onInputBarSubmitted,
                        onSubmitImage: controller.sendImageFromClipBoard,
                        focusNode: controller.inputFocus,
                        controller: controller.sendController,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.only(
                            left: 6.0,
                            right: 6.0,
                            bottom: 6.0,
                            top: 3.0,
                          ),
                          counter: const SizedBox.shrink(),
                          hintText: controller.room.encrypted
                              ? L10n.of(context).encryptedMessage
                              : L10n.of(context).unencryptedMessage,
                          hintMaxLines: 1,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          filled: false,
                        ),
                        onChanged: controller.onInputBarChanged,
                        suggestionEmojis:
                            getDefaultEmojiLocale(
                              AppSettings.emojiSuggestionLocale.value.isNotEmpty
                                  ? Locale(
                                      AppSettings.emojiSuggestionLocale.value,
                                    )
                                  : Localizations.localeOf(context),
                            ).fold(
                              [],
                              (emojis, category) =>
                                  emojis..addAll(category.emoji),
                            ),
                      ),
                    ),
                  ),
                  Container(
                    height: height,
                    width: height,
                    alignment: Alignment.center,
                    child:
                        PlatformInfos.platformCanRecord &&
                            !controller.sendController.text.isNotEmpty &&
                            controller.editEvent == null
                        ? HoverBuilder(
                            builder: (context, hovered) => IconButton(
                              tooltip: L10n.of(context).voiceMessage,
                              onPressed: hovered
                                  ? () => recordingViewModel.startRecording(
                                      controller.room,
                                    )
                                  : () => ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                          SnackBar(
                                            margin: EdgeInsets.only(
                                              bottom: height + 16,
                                              left: 16,
                                              right: 16,
                                              top: 16,
                                            ),
                                            showCloseIcon: true,
                                            content: Text(
                                              L10n.of(
                                                context,
                                              ).longPressToRecordVoiceMessage,
                                            ),
                                          ),
                                        ),
                              onLongPress: () => recordingViewModel
                                  .startRecording(controller.room),
                              style: IconButton.styleFrom(
                                backgroundColor: theme.bubbleColor,
                                foregroundColor: theme.onBubbleColor,
                              ),
                              icon: Icon(
                                hovered ? Icons.mic : Icons.mic_none_outlined,
                              ),
                            ),
                          )
                        : IconButton(
                            key: Key('send_button'),
                            tooltip: L10n.of(context).send,
                            onPressed: controller.send,
                            style: IconButton.styleFrom(
                              backgroundColor: theme.bubbleColor,
                              foregroundColor: theme.onBubbleColor,
                            ),
                            icon: const Icon(Icons.send_outlined),
                          ),
                  ),
                ],
        );
      },
    );
  }
}

class _ChatAccountPicker extends StatelessWidget {
  final ChatController controller;

  const _ChatAccountPicker(this.controller);

  void _popupMenuButtonSelected(String mxid, BuildContext context) {
    final client = Matrix.of(
      context,
    ).currentBundle!.firstWhere((cl) => cl!.userID == mxid, orElse: () => null);
    if (client == null) {
      Logs().w('Attempted to switch to a non-existing client $mxid');
      return;
    }
    controller.setSendingClient(client);
  }

  @override
  Widget build(BuildContext context) {
    final clients = controller.currentRoomBundle;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: FutureBuilder<Profile>(
        future: controller.sendingClient.fetchOwnProfile(),
        builder: (context, snapshot) => PopupMenuButton<String>(
          useRootNavigator: true,
          onSelected: (mxid) => _popupMenuButtonSelected(mxid, context),
          itemBuilder: (BuildContext context) => clients
              .map(
                (client) => PopupMenuItem(
                  value: client!.userID,
                  child: FutureBuilder<Profile>(
                    future: client.fetchOwnProfile(),
                    builder: (context, snapshot) => ListTile(
                      leading: Avatar(
                        mxContent: snapshot.data?.avatarUrl,
                        name:
                            snapshot.data?.displayName ??
                            client.userID!.localpart,
                        size: 20,
                      ),
                      title: Text(snapshot.data?.displayName ?? client.userID!),
                      contentPadding: const EdgeInsets.all(0),
                    ),
                  ),
                ),
              )
              .toList(),
          child: Avatar(
            mxContent: snapshot.data?.avatarUrl,
            name:
                snapshot.data?.displayName ??
                Matrix.of(context).client.userID!.localpart,
            size: 20,
          ),
        ),
      ),
    );
  }
}

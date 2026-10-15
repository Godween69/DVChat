// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: Экран переписки (внешний вид): шапка, список сообщений, поле ввода. Логика — chat.dart.

import 'dart:ui' as ui;

import 'package:dvchat/config/themes.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/chat/chat.dart';
import 'package:dvchat/pages/chat/chat_app_bar_list_tile.dart';
import 'package:dvchat/pages/chat/chat_app_bar_title.dart';
import 'package:dvchat/pages/chat/chat_event_list.dart';
import 'package:dvchat/pages/chat/pinned_events.dart';
import 'package:dvchat/pages/chat/reply_display.dart';
import 'package:dvchat/utils/account_config.dart';
import 'package:dvchat/utils/chat_background.dart';
import 'package:dvchat/utils/dv_admin.dart';
import 'package:dvchat/utils/localized_exception_extension.dart';
import 'package:dvchat/utils/room_archive_extension.dart';
import 'package:dvchat/widgets/chat_settings_popup_menu.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:dvchat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/stream_extension.dart';
import 'chat_emoji_picker.dart';
import 'chat_input_row.dart';

class ChatView extends StatelessWidget {
  final ChatController controller;

  const ChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (controller.room.membership == Membership.invite) {
      showFutureLoadingDialog(
        context: context,
        future: () => controller.room.join(),
        exceptionContext: ExceptionContext.joinRoom,
      );
    }
    final bottomSheetPadding = DvThemes.isColumnMode(context) ? 16.0 : 8.0;
    final scrollUpBannerEventId = controller.scrollUpBannerEventId;

    final accountConfig = Matrix.of(context).client.applicationAccountConfig;

    return PopScope(
      canPop:
          controller.selectedEvents.isEmpty &&
          !controller.showEmojiPicker &&
          controller.activeThreadId == null,
      onPopInvokedWithResult: (pop, _) async {
        if (pop) return;
        if (controller.selectedEvents.isNotEmpty) {
          controller.clearSelectedEvents();
        } else if (controller.showEmojiPicker) {
          controller.emojiPickerAction();
        } else if (controller.activeThreadId != null) {
          controller.closeThread();
        }
      },
      child: StreamBuilder(
        stream: controller.room.client.onRoomState.stream
            .where((update) => update.roomId == controller.room.id)
            .rateLimit(const Duration(seconds: 1)),
        builder: (context, snapshot) => FutureBuilder(
          future: controller.loadTimelineFuture,
          builder: (BuildContext context, snapshot) {
            var appbarBottomHeight = 0.0;
            final activeThreadId = controller.activeThreadId;
            if (activeThreadId != null) {
              appbarBottomHeight += ChatAppBarListTile.fixedHeight;
            }
            if (controller.room.pinnedEventIds.isNotEmpty &&
                activeThreadId == null) {
              appbarBottomHeight += ChatAppBarListTile.fixedHeight;
            }
            if (scrollUpBannerEventId != null && activeThreadId == null) {
              appbarBottomHeight += ChatAppBarListTile.fixedHeight;
            }
            return Scaffold(
              key: Key('chat_page'),
              extendBodyBehindAppBar: true,
              appBar: AppBar(
                shape: DvThemes.isColumnMode(context)
                    ? Border(
                        bottom: BorderSide(color: theme.dividerColor, width: 1),
                      )
                    : null,
                actionsIconTheme: IconThemeData(
                  color: controller.selectedEvents.isEmpty
                      ? null
                      : theme.colorScheme.onTertiaryContainer,
                ),
                backgroundColor: controller.selectedEvents.isEmpty
                    ? controller.activeThreadId != null
                          ? theme.colorScheme.secondaryContainer
                          : theme.colorScheme.surface.withAlpha(240)
                    : theme.colorScheme.tertiaryContainer,
                automaticallyImplyLeading: false,
                leading: controller.selectMode
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: controller.clearSelectedEvents,
                        tooltip: L10n.of(context).close,
                        color: theme.colorScheme.onTertiaryContainer,
                      )
                    : activeThreadId != null
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: controller.closeThread,
                        tooltip: L10n.of(context).backToMainChat,
                        color: theme.colorScheme.onSecondaryContainer,
                      )
                    : DvThemes.isColumnMode(context)
                    ? null
                    : const Center(child: BackButton()),
                titleSpacing: DvThemes.isColumnMode(context) ? 24 : 0,
                title: ChatAppBarTitle(controller),
                actions: [
                  if (controller.selectMode) ...[
                    if (controller.canEditSelectedEvents)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: L10n.of(context).edit,
                        onPressed: controller.editSelectedEventAction,
                      ),

                    IconButton(
                      icon: const Icon(Icons.copy_outlined),
                      tooltip: L10n.of(context).copyToClipboard,
                      onPressed: controller.copyEventsAction,
                    ),
                    if (controller.selectedEvents.length == 1 &&
                        controller.canPinSelectedEvents)
                      IconButton(
                        icon: Icon(
                          controller.selectedIsPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                        ),
                        tooltip: controller.selectedIsPinned
                            ? L10n.of(context).unpin
                            : L10n.of(context).pinMessage,
                        onPressed: controller.pinEvent,
                      ),
                    if (controller.selectedEvents.length == 1 &&
                        controller.canSaveSelectedEvent)
                      IconButton(
                        icon: const Icon(Icons.download_outlined),
                        tooltip: L10n.of(context).downloadFile,
                        onPressed: () => controller.saveSelectedEvent(context),
                      ),
                    if (controller.selectedEvents.length == 1 &&
                        isDvAdmin(controller.room.client))
                      IconButton(
                        icon: const Icon(Icons.info_outlined),
                        tooltip: L10n.of(context).messageInfo,
                        onPressed: () {
                          controller.showEventInfo();
                          controller.clearSelectedEvents();
                        },
                      ),
                    if (controller.canRedactSelectedEvents)
                      IconButton(
                        icon: const Icon(Icons.delete_outlined),
                        tooltip: L10n.of(context).redactMessage,
                        onPressed: controller.redactEventsAction,
                      ),
                  ] else if (!controller.room.isArchived &&
                      !controller.room.isHistoryOnly) ...[
                    ChatSettingsPopupMenu(controller.room, true),
                  ],
                ],
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(appbarBottomHeight),
                  child: AnimatedSize(
                    duration: DvThemes.animationDuration,
                    curve: DvThemes.animationCurve,
                    child: Column(
                      mainAxisSize: .min,
                      children: [
                        PinnedEvents(controller),
                        if (activeThreadId != null)
                          SizedBox(
                            height: ChatAppBarListTile.fixedHeight,
                            child: Center(
                              child: TextButton.icon(
                                onPressed: () =>
                                    controller.scrollToEventId(activeThreadId),
                                icon: const Icon(Icons.message),
                                label: Text(L10n.of(context).replyInThread),
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      theme.colorScheme.onSecondaryContainer,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (scrollUpBannerEventId != null &&
                            activeThreadId == null)
                          ChatAppBarListTile(
                            leading: IconButton(
                              color: theme.colorScheme.onSurfaceVariant,
                              icon: const Icon(Icons.close),
                              tooltip: L10n.of(context).close,
                              onPressed: () {
                                controller.discardScrollUpBannerEventId();
                                controller.setReadMarker();
                              },
                            ),
                            title: L10n.of(context).jumpToLastReadMessage,
                            trailing: TextButton(
                              onPressed: () {
                                controller.scrollToEventId(
                                  scrollUpBannerEventId,
                                );
                                controller.discardScrollUpBannerEventId();
                              },
                              child: Text(L10n.of(context).jump),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              floatingActionButton:
                  controller.showScrollDownButton &&
                      controller.selectedEvents.isEmpty
                  ? Padding(
                      padding: EdgeInsets.only(
                        bottom: theme.appBarTheme.toolbarHeight ?? 56,
                      ),
                      child: FloatingActionButton(
                        onPressed: controller.scrollDown,
                        heroTag: null,
                        mini: true,
                        backgroundColor: theme.colorScheme.surface,
                        foregroundColor: theme.colorScheme.onSurface,
                        child: const Icon(Icons.arrow_downward_outlined),
                      ),
                    )
                  : null,
              body: NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (SizeChangedLayoutNotification notification) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => controller.updateInputBarHeight(),
                  );
                  return true;
                },
                child: SafeArea(
                  top: false,
                  child: Stack(
                    children: <Widget>[
                      if (dvChatBackground != null)
                        Positioned.fill(
                          child: ColoredBox(color: dvChatBackground!),
                        ),
                      if (accountConfig.wallpaperUrl != null)
                        Opacity(
                          opacity: accountConfig.wallpaperOpacity ?? 0.5,
                          child: ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(
                              sigmaX: accountConfig.wallpaperBlur ?? 0.0,
                              sigmaY: accountConfig.wallpaperBlur ?? 0.0,
                            ),
                            child: MxcImage(
                              cacheKey: accountConfig.wallpaperUrl.toString(),
                              uri: accountConfig.wallpaperUrl,
                              fit: BoxFit.cover,
                              height: MediaQuery.sizeOf(context).height,
                              width: MediaQuery.sizeOf(context).width,
                              isThumbnail: false,
                              placeholder: (_) => Container(),
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: controller.clearSingleSelectedEvent,
                        child: ChatEventList(controller: controller),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: SizeChangedLayoutNotifier(
                          child: Container(
                            key: controller.inputBarKey,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  (dvChatBackground ??
                                          theme.colorScheme.surface)
                                      .withAlpha(0),
                                  dvChatBackground ?? theme.colorScheme.surface,
                                  dvChatBackground ?? theme.colorScheme.surface,
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Container(
                              margin: EdgeInsets.all(bottomSheetPadding),
                              constraints: const BoxConstraints(
                                maxWidth: DvThemes.maxTimelineWidth,
                              ),
                              child: controller.room.isExtinct
                                  ? ElevatedButton.icon(
                                      icon: const Icon(Icons.chevron_right),
                                      label: Text(
                                        L10n.of(context).enterNewChat,
                                      ),
                                      onPressed: controller.goToNewRoomAction,
                                    )
                                  // Закрытый чат: внизу ничего, только лента выше
                                  : controller.room.isHistoryOnly
                                  ? const SizedBox.shrink()
                                  : controller.room.canSendDefaultMessages &&
                                        controller.room.membership ==
                                            Membership.join
                                  ? Material(
                                      clipBehavior: Clip.hardEdge,
                                      color:
                                          controller.selectedEvents.isNotEmpty
                                          ? theme.colorScheme.tertiaryContainer
                                          : theme.colorScheme.surfaceContainer,
                                      borderRadius: BorderRadius.circular(32),
                                      child: Column(
                                        mainAxisSize: .min,
                                        children: [
                                          ReplyDisplay(controller),
                                          ChatInputRow(controller),
                                          ChatEmojiPicker(controller),
                                        ],
                                      ),
                                    )
                                  : SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

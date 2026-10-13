// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:dvchat/config/themes.dart';
import 'package:dvchat/pages/archive/archive.dart';
import 'package:dvchat/pages/bootstrap/bootstrap_page.dart';
import 'package:dvchat/pages/chat/chat.dart';
import 'package:dvchat/pages/chat_access_settings/chat_access_settings_controller.dart';
import 'package:dvchat/pages/chat_details/chat_details.dart';
import 'package:dvchat/pages/chat_encryption_settings/chat_encryption_settings.dart';
import 'package:dvchat/pages/chat_list/chat_list.dart';
import 'package:dvchat/pages/chat_members/chat_members.dart';
import 'package:dvchat/pages/chat_permissions_settings/chat_permissions_settings.dart';
import 'package:dvchat/pages/chat_search/chat_search_page.dart';
import 'package:dvchat/pages/device_settings/device_settings.dart';
import 'package:dvchat/pages/friends/friends_page.dart';
import 'package:dvchat/pages/intro/intro_page_presenter.dart';
import 'package:dvchat/pages/invitation_selection/invitation_selection.dart';
import 'package:dvchat/pages/new_group/new_group.dart';
import 'package:dvchat/pages/new_private_chat/new_private_chat.dart';
import 'package:dvchat/pages/settings/settings.dart';
import 'package:dvchat/pages/settings_3pid/settings_3pid.dart';
import 'package:dvchat/pages/settings_chat/settings_chat.dart';
import 'package:dvchat/pages/settings_emotes/settings_emotes.dart';
import 'package:dvchat/pages/settings_feedback/settings_feedback.dart';
import 'package:dvchat/pages/settings_homeserver/settings_homeserver.dart';
import 'package:dvchat/pages/settings_ignore_list/settings_ignore_list.dart';
import 'package:dvchat/pages/settings_notifications/settings_notifications.dart';
import 'package:dvchat/pages/settings_password/settings_password.dart';
import 'package:dvchat/pages/settings_security/settings_security.dart';
import 'package:dvchat/pages/settings_style/settings_style.dart';
import 'package:dvchat/widgets/layouts/empty_page.dart';
import 'package:dvchat/widgets/layouts/two_column_layout.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:dvchat/widgets/share_scaffold_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

abstract class AppRoutes {
  static FutureOr<String?> loggedInRedirect(
    BuildContext context,
    GoRouterState state,
  ) => Matrix.of(context).widget.clients.any((client) => client.isLogged())
      ? '/rooms'
      : null;

  static FutureOr<String?> loggedOutRedirect(
    BuildContext context,
    GoRouterState state,
  ) => Matrix.of(context).widget.clients.any((client) => client.isLogged())
      ? null
      : '/home';

  AppRoutes();

  static final List<RouteBase> routes = [
    GoRoute(
      path: '/',
      redirect: (context, state) =>
          Matrix.of(context).widget.clients.any((client) => client.isLogged())
          ? '/rooms'
          : '/home',
    ),
    GoRoute(
      path: '/home',
      pageBuilder: (context, state) =>
          defaultPageBuilder(context, state, const IntroPagePresenter()),
      redirect: loggedInRedirect,
    ),
    GoRoute(
      path: '/backup',
      redirect: loggedOutRedirect,
      pageBuilder: (context, state) => defaultPageBuilder(
        context,
        state,
        BootstrapPage(reset: state.uri.queryParameters['reset'] == 'true'),
      ),
    ),
    ShellRoute(
      // Never use a transition on the shell route. Changing the PageBuilder
      // here based on a MediaQuery causes the child to briefly be rendered
      // twice with the same GlobalKey, blowing up the rendering.
      pageBuilder: (context, state, child) => noTransitionPageBuilder(
        context,
        state,
        FluffyThemes.isColumnMode(context) &&
                state.fullPath?.startsWith('/rooms/settings') == false
            ? TwoColumnLayout(
                mainView: ChatList(activeChat: state.pathParameters['roomid']),
                sideView: child,
              )
            : child,
      ),
      routes: [
        GoRoute(
          path: '/rooms',
          redirect: loggedOutRedirect,
          pageBuilder: (context, state) => defaultPageBuilder(
            context,
            state,
            FluffyThemes.isColumnMode(context)
                ? const EmptyPage()
                : ChatList(activeChat: state.pathParameters['roomid']),
          ),
          routes: [
            GoRoute(
              path: 'archive',
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const Archive()),
              routes: [
                GoRoute(
                  path: ':roomid',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatPage(
                      key: ValueKey(state.uri),
                      roomId: state.pathParameters['roomid']!,
                      eventId: state.uri.queryParameters['event'],
                      timeline: state.extra as Timeline?,
                      action: state.uri.queryParameters['action'],
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
              ],
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'friends',
              pageBuilder: (context, state) =>
                  defaultPageBuilder(context, state, const FriendsPage()),
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'newprivatechat',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                NewPrivateChat(
                  key: ValueKey('new_chat_${state.uri.fragment}'),
                  deeplink: state.uri.fragment,
                ),
              ),
              redirect: loggedOutRedirect,
            ),
            GoRoute(
              path: 'newgroup',
              pageBuilder: (context, state) => defaultPageBuilder(
                context,
                state,
                NewGroup(spaceId: state.uri.queryParameters['space_id']),
              ),
              redirect: loggedOutRedirect,
            ),
            ShellRoute(
              pageBuilder: (context, state, child) => defaultPageBuilder(
                context,
                state,
                FluffyThemes.isColumnMode(context)
                    ? TwoColumnLayout(
                        mainView: Settings(key: state.pageKey),
                        sideView: child,
                        hasNavigationRail: false,
                      )
                    : child,
              ),
              routes: [
                GoRoute(
                  path: 'settings',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    FluffyThemes.isColumnMode(context)
                        ? const EmptyPage()
                        : const Settings(),
                  ),
                  routes: [
                    GoRoute(
                      path: 'notifications',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsNotifications(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'feedback',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsFeedback(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'style',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsStyle(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'devices',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const DevicesSettings(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'chat',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsChat(),
                      ),
                      routes: [
                        GoRoute(
                          path: 'emotes',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            EmotesSettings(
                              roomId: state.pathParameters['roomid'],
                            ),
                          ),
                        ),
                      ],
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'homeserver',
                      pageBuilder: (context, state) {
                        return defaultPageBuilder(
                          context,
                          state,
                          const SettingsHomeserver(),
                        );
                      },
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'security',
                      redirect: loggedOutRedirect,
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const SettingsSecurity(),
                      ),
                      routes: [
                        GoRoute(
                          path: 'password',
                          pageBuilder: (context, state) {
                            return defaultPageBuilder(
                              context,
                              state,
                              const SettingsPassword(),
                            );
                          },
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: 'ignorelist',
                          pageBuilder: (context, state) {
                            return defaultPageBuilder(
                              context,
                              state,
                              SettingsIgnoreList(
                                initialUserId: state.extra?.toString(),
                              ),
                            );
                          },
                          redirect: loggedOutRedirect,
                        ),
                        GoRoute(
                          path: '3pid',
                          pageBuilder: (context, state) => defaultPageBuilder(
                            context,
                            state,
                            const Settings3Pid(),
                          ),
                          redirect: loggedOutRedirect,
                        ),
                      ],
                    ),
                  ],
                  redirect: loggedOutRedirect,
                ),
              ],
            ),
            GoRoute(
              path: ':roomid',
              pageBuilder: (context, state) {
                final body = state.uri.queryParameters['body'];
                var shareItems = state.extra is List<ShareItem>
                    ? state.extra as List<ShareItem>
                    : null;
                if (body != null && body.isNotEmpty) {
                  shareItems ??= [];
                  shareItems.add(TextShareItem(body));
                }
                return defaultPageBuilder(
                  context,
                  state,
                  ChatPage(
                    key: ValueKey(state.uri),
                    roomId: state.pathParameters['roomid']!,
                    shareItems: shareItems,
                    eventId: state.uri.queryParameters['event'],
                    action: state.uri.queryParameters['action'],
                  ),
                );
              },
              redirect: loggedOutRedirect,
              routes: [
                GoRoute(
                  path: 'search',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatSearchPage(roomId: state.pathParameters['roomid']!),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'encryption',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    const ChatEncryptionSettings(),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'invite',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    InvitationSelection(
                      roomId: state.pathParameters['roomid']!,
                    ),
                  ),
                  redirect: loggedOutRedirect,
                ),
                GoRoute(
                  path: 'details',
                  pageBuilder: (context, state) => defaultPageBuilder(
                    context,
                    state,
                    ChatDetails(roomId: state.pathParameters['roomid']!),
                  ),
                  routes: [
                    GoRoute(
                      path: 'access',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        ChatAccessSettings(
                          roomId: state.pathParameters['roomid']!,
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'members',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        ChatMembersPage(
                          roomId: state.pathParameters['roomid']!,
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'permissions',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        const ChatPermissionsSettings(),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'invite',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        InvitationSelection(
                          roomId: state.pathParameters['roomid']!,
                        ),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                    GoRoute(
                      path: 'emotes',
                      pageBuilder: (context, state) => defaultPageBuilder(
                        context,
                        state,
                        EmotesSettings(roomId: state.pathParameters['roomid']),
                      ),
                      redirect: loggedOutRedirect,
                    ),
                  ],
                  redirect: loggedOutRedirect,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ];

  static Page noTransitionPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) => NoTransitionPage(
    key: state.pageKey,
    restorationId: state.pageKey.value,
    child: child,
  );

  static Page defaultPageBuilder(
    BuildContext context,
    GoRouterState state,
    Widget child,
  ) {
    final clientName = state.uri.queryParameters['client'];
    if (clientName != null) {
      final matrix = Matrix.of(context);
      final client = matrix.getClientByName(clientName);
      if (client != null) matrix.setActiveClient(client);
    }
    return FluffyThemes.isColumnMode(context)
        ? noTransitionPageBuilder(context, state, child)
        : MaterialPage(
            key: state.pageKey,
            restorationId: state.pageKey.value,
            child: child,
          );
  }
}

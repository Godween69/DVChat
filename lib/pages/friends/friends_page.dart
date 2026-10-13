// DVChat: экран «Друзья»: список, заявки, добавление по ID или QR, открытие чата

import 'dart:async';

import 'package:dvchat/config/app_config.dart';
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:dvchat/utils/best_friends.dart';
import 'package:dvchat/utils/dv_api.dart';
import 'package:dvchat/utils/room_archive_extension.dart';
import 'package:dvchat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:dvchat/widgets/dv_my_id.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:zxing2/qrcode.dart';

const _scanMarker = 'scan';
const _imageMarker = 'image';

/// Разбирает строку из QR или поля ввода. Ссылку входа в аккаунт не принимаем.
({String? id, String? error}) parseFriendCode(String raw) {
  final text = raw.trim();
  if (text.toLowerCase().startsWith(
    '${AppConfig.loginLinkScheme}://${AppConfig.loginLinkHost}',
  )) {
    return (
      id: null,
      error:
          'Это ссылка для входа в аккаунт, а не код друга. Её нельзя использовать.',
    );
  }
  final match = RegExp(
    '^(?:${AppConfig.loginLinkScheme}://add/)?(\\d{10})\$',
  ).firstMatch(text);
  if (match == null) return (id: null, error: 'Это не код друга DVChat');
  return (id: match.group(1), error: null);
}

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsData {
  final List<String> friends;
  final List<String> requests;
  final bool allUsers;
  const _FriendsData(this.friends, this.requests, this.allUsers);
}

class _FriendsPageState extends State<FriendsPage> {
  late Future<_FriendsData> _future;
  final Map<String, Future<Profile>> _profiles = {};

  /// «Лучшие друзья» (личный список, хранится в данных аккаунта)
  late Set<String> _best;

  Client get _client => Matrix.of(context).client;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
    _best = {..._client.bestFriends};
  }

  Future<Profile> _profile(String userId) =>
      _profiles.putIfAbsent(userId, () => _client.getProfileFromUserId(userId));

  static List<String> _ids(Object? value) => value is List
      ? value
            .whereType<Map<String, Object?>>()
            .map((m) => m['user_id'])
            .whereType<String>()
            .toList()
      : <String>[];

  Future<_FriendsData> _fetch() async {
    final api = DvApi(_client);
    final friends = await api.get('friends');
    final requests = await api.get('requests');
    return _FriendsData(
      _ids(friends['friends']),
      _ids(requests['requests']),
      friends['all_users'] == true,
    );
  }

  void _reload() {
    setState(() {
      _future = _fetch();
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openChat(String userId) async {
    final client = _client;
    // Чат с этим человеком уже есть: просто открываем его, сервер не спрашиваем
    final existingId = client.getDirectChatFromUserId(userId);
    final existing =
        (existingId == null ? null : client.getRoomById(existingId)) ??
        client.rooms
            .where(
              (r) =>
                  r.membership == Membership.join &&
                  r.isDirectChat &&
                  r.directChatMatrixID == userId,
            )
            .firstOrNull;
    if (existing != null && existing.membership == Membership.join) {
      context.go('/rooms/${existing.id}');
      return;
    }
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final res = await DvApi(client).post('chat', {'user_id': userId});
        final roomId = res['room_id'];
        if (roomId is! String) {
          throw const DvApiException(500, '', 'Сервер не вернул чат');
        }
        // Ожидание ограничено: вечная крутилка хуже понятной ошибки
        await client
            .waitForRoomInSync(roomId, join: true)
            .timeout(const Duration(seconds: 30));
        return roomId;
      },
    );
    final roomId = result.result;
    if (roomId == null || !mounted) return;
    context.go('/rooms/$roomId');
  }

  Future<void> _answer(String userId, bool accept) async {
    final client = _client;
    await showFutureLoadingDialog(
      context: context,
      future: () => DvApi(
        client,
      ).post('requests/answer', {'user_id': userId, 'accept': accept}),
    );
    if (mounted) _reload();
  }

  Future<void> _addFriend() async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) => const _AddFriendDialog(),
    );
    if (input == null || !mounted) return;
    if (input == _scanMarker) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => QrScannerModal(
            onScan: (code) {
              // Сканер закрывается сам до вызова onScan
              if (!mounted) return;
              final parsed = parseFriendCode(code);
              final id = parsed.id;
              if (id == null) {
                _snack(parsed.error ?? 'Не удалось прочитать код');
                return;
              }
              unawaited(_submit(id, viaQr: true));
            },
          ),
        ),
      );
      return;
    }
    if (input == _imageMarker) {
      await _scanFromImage();
      return;
    }
    await _submit(input, viaQr: false);
  }

  /// Читает QR-код из картинки в галерее (скриншот или фото кода друга).
  Future<void> _scanFromImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    final text = await compute(_decodeQrFromBytes, bytes);
    if (!mounted) return;
    if (text == null) {
      _snack('На картинке не найден QR-код');
      return;
    }
    final parsed = parseFriendCode(text);
    final id = parsed.id;
    if (id == null) {
      _snack(parsed.error ?? 'Не удалось прочитать код');
      return;
    }
    await _submit(id, viaQr: true);
  }

  Future<void> _submit(String id, {required bool viaQr}) async {
    if (!mounted) return;
    final client = _client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () =>
          DvApi(client).post('friends/add', {'dv_id': id, 'via_qr': viaQr}),
    );
    final status = result.result?['status'];
    if (!mounted) return;
    if (status == 'added') {
      _snack('Друг добавлен');
    } else if (status == 'requested') {
      _snack('Заявка отправлена: друг увидит её у себя в списке заявок');
    } else if (status == 'already') {
      _snack('Этот человек уже у вас в друзьях');
    }
    _reload();
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  Widget _userTile(
    String id, {
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Widget? trailing,
  }) => FutureBuilder<Profile>(
    future: _profile(id),
    builder: (context, snapshot) {
      final profile = snapshot.data;
      final name = profile?.displayName ?? id.localpart ?? id;
      return ListTile(
        leading: Avatar(
          mxContent: profile?.avatarUrl,
          name: name,
          client: _client,
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
        onLongPress: onLongPress,
        trailing: trailing,
      );
    },
  );

  Widget _friendTile(String id, bool allUsers) => _userTile(
    id,
    onTap: () => _openChat(id),
    onLongPress: () => _friendMenu(id, allUsers),
  );

  Future<String> _nameOf(String id) async {
    try {
      return (await _profile(id)).displayName ?? id.localpart ?? id;
    } catch (_) {
      return id.localpart ?? id;
    }
  }

  /// Меню по долгому нажатию: лучшие и удаление из друзей
  Future<void> _friendMenu(String id, bool allUsers) async {
    final isBest = _best.contains(id);
    final error = Theme.of(context).colorScheme.error;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isBest ? Icons.star : Icons.star_outline),
              title: Text(isBest ? 'Убрать из лучших' : 'В лучшие'),
              onTap: () => Navigator.of(context).pop('best'),
            ),
            if (!allUsers)
              ListTile(
                leading: Icon(Icons.person_remove_outlined, color: error),
                title: Text(
                  'Удалить из друзей',
                  style: TextStyle(color: error),
                ),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'best') {
      setState(() {
        if (isBest) {
          _best.remove(id);
        } else {
          _best.add(id);
        }
      });
      try {
        await _client.setBestFriend(id, best: !isBest);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          if (isBest) {
            _best.add(id);
          } else {
            _best.remove(id);
          }
        });
        _snack('Не удалось сохранить: $e');
      }
    } else if (action == 'remove') {
      await _removeFriend(id);
    }
  }

  Future<void> _removeFriend(String userId) async {
    final name = await _nameOf(userId);
    if (!mounted) return;
    final ok = await showOkCancelAlertDialog(
      context: context,
      title: 'Удалить $name из друзей?',
      message:
          'Вся переписка с этим человеком будет удалена у вас и отправлена в Архив '
          'у него, без возможности продолжить. Чтобы общаться снова, нужно заново '
          'подружиться через QR-код и начать новый чат.',
      okLabel: 'Удалить',
      cancelLabel: 'Отмена',
      isDestructive: true,
    );
    if (ok != OkCancelResult.ok || !mounted) return;
    final client = _client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        // Сначала сервер: если он отказал, чаты не трогаем
        await DvApi(client).post('friends/remove', {'user_id': userId});
        final rooms = client.rooms
            .where(
              (r) =>
                  r.membership == Membership.join &&
                  r.isDirectChat &&
                  r.directChatMatrixID == userId &&
                  r.isAbandonedDMRoom != true &&
                  !r.isSupportRoom,
            )
            .toList();
        for (final room in rooms) {
          try {
            await room.deleteForMe(unfriend: true);
          } catch (e, s) {
            Logs().w('DVChat: не удалось удалить чат ${room.id}', e, s);
          }
        }
        if (_best.contains(userId)) {
          await client.setBestFriend(userId, best: false);
        }
      },
    );
    if (!mounted) return;
    if (result.error == null) {
      setState(() => _best.remove(userId));
      _snack('$name удалён(а) из друзей');
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Друзья'),
        leading: Center(
          child: BackButton(onPressed: () => context.go('/rooms')),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Добавить друга',
            onPressed: _addFriend,
          ),
        ],
      ),
      body: FutureBuilder<_FriendsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _reload,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          final best = data.friends.where(_best.contains).toList();
          final rest = data.friends.where((id) => !_best.contains(id)).toList();
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              children: [
                const DvMyIdTile(),
                const Divider(height: 1),
                if (data.requests.isNotEmpty) ...[
                  _header('Заявки в друзья'),
                  for (final id in data.requests)
                    _userTile(
                      id,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check_circle_outline),
                            tooltip: 'Принять',
                            onPressed: () => _answer(id, true),
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined),
                            tooltip: 'Отклонить',
                            onPressed: () => _answer(id, false),
                          ),
                        ],
                      ),
                    ),
                ],
                if (best.isNotEmpty) ...[
                  _header('Лучшие'),
                  for (final id in best) _friendTile(id, data.allUsers),
                ],
                _header(data.allUsers ? 'Все пользователи' : 'Друзья'),
                if (data.friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Пока нет друзей. Нажмите значок «добавить» вверху: '
                      'введите ID или отсканируйте QR-код.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final id in rest) _friendTile(id, data.allUsers),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AddFriendDialog extends StatefulWidget {
  const _AddFriendDialog();

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => RegExp(r'^\d{10}$').hasMatch(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить друга'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            maxLength: 10,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'ID друга (10 цифр)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(_scanMarker),
            icon: const Icon(Icons.qr_code_scanner_outlined),
            label: const Text('Сканировать QR-код'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(_imageMarker),
            icon: const Icon(Icons.image_outlined),
            label: const Text('QR из картинки'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).cancel),
        ),
        TextButton(
          onPressed: _valid
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}

/// Декодирует QR из байтов картинки (запускается в отдельном потоке).
String? _decodeQrFromBytes(Uint8List bytes) {
  try {
    var image = img.decodeImage(bytes);
    if (image == null) return null;
    // Слишком большие фото уменьшаем: так быстрее и надёжнее
    if (image.width > 1400 || image.height > 1400) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? 1400 : null,
        height: image.height > image.width ? 1400 : null,
      );
    }
    final source = RGBLuminanceSource(
      image.width,
      image.height,
      image
          .convert(numChannels: 4)
          .getBytes(order: img.ChannelOrder.abgr)
          .buffer
          .asInt32List(),
    );
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    return QRCodeReader().decode(bitmap).text;
  } catch (_) {
    return null;
  }
}

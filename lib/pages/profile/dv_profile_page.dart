// SPDX-License-Identifier: AGPL-3.0-or-later

// DVChat: профиль человека. Свой: фото, имя, день рождения, мой ID и QR.
// Чужой (друг): фото, имя, день рождения, ID и QR, переключатель уведомлений.

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPicker;
import 'package:dvchat/l10n/l10n.dart';
import 'package:dvchat/utils/dv_api.dart';
import 'package:dvchat/utils/dv_profile_api.dart';
import 'package:dvchat/utils/file_selector.dart';
import 'package:dvchat/utils/platform_infos.dart';
import 'package:dvchat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:dvchat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:dvchat/widgets/avatar_crop_dialog.dart';
import 'package:dvchat/widgets/dv_my_id.dart';
import 'package:dvchat/widgets/dv_qr.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:dvchat/widgets/mxc_image_viewer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum _AvatarAction { camera, file, remove }

/// Размер большой аватарки в профиле
const double _profileAvatarSize = Avatar.defaultSize * 3.8;

class DvProfilePage extends StatefulWidget {
  const DvProfilePage({required this.userId, this.from, super.key});

  final String userId;

  /// Где на экране была маленькая аватарка: от этого места большая плавно «вылетает»
  final Rect? from;

  /// Открыть профиль поверх всего приложения (плавное появление)
  static Future<void> open(BuildContext context, String userId, {Rect? from}) {
    if (userId.isEmpty) return Future.value();
    final fly = from != null;
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration(milliseconds: fly ? 340 : 180),
        reverseTransitionDuration: Duration(milliseconds: fly ? 280 : 150),
        pageBuilder: (_, _, _) => DvProfilePage(userId: userId, from: from),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: fly
              ? animation.drive(
                  CurveTween(
                    curve: const Interval(0, 0.55, curve: Curves.easeOut),
                  ),
                )
              : animation,
          child: child,
        ),
      ),
    );
  }

  @override
  State<DvProfilePage> createState() => _DvProfilePageState();
}

class _DvProfilePageState extends State<DvProfilePage> {
  Client get _client => Matrix.of(context).client;
  bool get _mine => widget.userId == _client.userID;

  Future<Profile>? _profile;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _profile ??= _client.getProfileFromUserId(widget.userId);
    if (!_started) {
      _started = true;
      unawaited(_loadBirthday());
    }
  }

  Future<void> _loadBirthday() async {
    try {
      await DvProfiles.load(_client, [widget.userId]);
    } catch (e) {
      Logs().v('DVChat: профиль не загружен', e);
    }
    if (mounted) setState(() {});
  }

  void _refreshProfile() {
    final id = widget.userId;
    setState(() {
      _profile = _client.database
          .markUserProfileAsOutdated(id)
          .then((_) => _client.getProfileFromUserId(id));
    });
  }

  Future<void> _editName() async {
    final l10n = L10n.of(context);
    final profile = await _profile;
    if (!mounted) return;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.editDisplayname,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: profile?.displayName ?? _client.userID!.localpart,
    );
    if (input == null || !mounted) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => _client.setProfileField(_client.userID!, 'displayname', {
        'displayname': input,
      }),
    );
    if (success.error == null) _refreshProfile();
  }

  Future<void> _changeAvatar() async {
    final l10n = L10n.of(context);
    final profile = await _profile;
    if (!mounted) return;
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: _AvatarAction.camera,
          label: l10n.openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: _AvatarAction.file,
        label: l10n.openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (profile?.avatarUrl != null)
        AdaptiveModalAction(
          value: _AvatarAction.remove,
          label: l10n.removeYourAvatar,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<_AvatarAction>(
            context: context,
            title: l10n.changeYourAvatar,
            cancelLabel: l10n.cancel,
            actions: actions,
          );
    if (action == null || !mounted) return;
    if (action == _AvatarAction.remove) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () => _client.setAvatar(null),
      );
      if (success.error == null) _refreshProfile();
      return;
    }
    MatrixFile file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == _AvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
    } else {
      if (!mounted) return;
      final result = await selectFiles(context, type: FileType.image);
      if (result.isEmpty) return;
      final picked = result.first;
      file = MatrixFile(bytes: await picked.readAsBytes(), name: picked.name);
    }
    if (!mounted) return;
    final cropped = await cropAvatar(context, file.bytes);
    if (cropped == null || !mounted) return;
    file = MatrixFile(bytes: cropped, name: 'avatar.png');
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => _client.setAvatar(file),
    );
    if (success.error == null) _refreshProfile();
  }

  /// Просмотр своего фото: плавно выплывает из темноты
  void _openViewer(Uri avatar) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) =>
            ColoredBox(color: Colors.black, child: MxcImageViewer(avatar)),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Future<void> _pickBirthday() async {
    final result = await showDialog<_BirthdayResult>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: _BirthdaySheet(
          initial: DvProfiles.cachedBirthday(widget.userId),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final done = await showFutureLoadingDialog(
      context: context,
      future: () => DvProfiles.saveBirthday(_client, result.value),
    );
    if (done.error == null && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: FutureBuilder<Profile>(
        future: _profile,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          final name =
              profile?.displayName ?? widget.userId.localpart ?? widget.userId;
          final avatar = profile?.avatarUrl;
          final birthday = DvProfiles.cachedBirthday(widget.userId);
          final friendId = DvProfiles.cachedDvId(widget.userId);
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Center(
                child: _FlyIn(
                  from: widget.from,
                  size: _profileAvatarSize,
                  child: Stack(
                    children: [
                      Avatar(
                        mxContent: avatar,
                        name: name,
                        client: _client,
                        size: _profileAvatarSize,
                        onTap: avatar == null
                            ? null
                            : () => _openViewer(avatar),
                      ),
                      if (_mine && profile != null)
                        Positioned(
                          bottom: 3,
                          right: 3,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: theme.scaffoldBackgroundColor,
                              shape: BoxShape.circle,
                            ),
                            child: Material(
                              color: theme.colorScheme.primary,
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: _changeAvatar,
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Center(
                                    child: Icon(
                                      Icons.camera_alt_outlined,
                                      size: 22,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: _mine
                    ? TextButton.icon(
                        onPressed: _editName,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurface,
                          iconColor: theme.colorScheme.onSurface,
                        ),
                        label: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 22),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              if (_mine) ...[
                ListTile(
                  leading: const Icon(Icons.cake_outlined),
                  title: const Text('День рождения'),
                  subtitle: Text(birthday?.text ?? 'Не указан'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickBirthday,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
                  child: Text(
                    'Чтобы друзья могли получать уведомления о вашем дне рождения.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const DvMyIdTile(),
                const DvBirthdayNotifyTile(),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.cake_outlined),
                  title: const Text('День рождения'),
                  subtitle: Text(birthday?.text ?? 'Не указан'),
                ),
                if (friendId != null) _FriendIdTile(friendId),
                const DvBirthdayNotifyTile(),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Большая аватарка «вылетает» от места маленькой (в настройках) к своему месту в центре
class _FlyIn extends StatelessWidget {
  const _FlyIn({required this.from, required this.size, required this.child});

  final Rect? from;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = from;
    final animation = ModalRoute.of(context)?.animation;
    if (start == null || animation == null) return child;
    // Место аватарки в профиле: по центру, под панелью заголовка и отступом списка
    final target = Offset(
      MediaQuery.sizeOf(context).width / 2,
      MediaQuery.paddingOf(context).top + kToolbarHeight + 16 + size / 2,
    );
    final curved = animation.drive(CurveTween(curve: Curves.easeInOutCubic));
    final startScale = start.width / size;
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) {
        final t = curved.value;
        final shift = Offset.lerp(start.center - target, Offset.zero, t)!;
        return Transform.translate(
          offset: shift,
          child: Transform.scale(
            scale: startScale + (1 - startScale) * t,
            child: child,
          ),
        );
      },
    );
  }
}

/// ID друга и его QR-код
class _FriendIdTile extends StatelessWidget {
  const _FriendIdTile(this.id);

  final String id;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.qr_code_2_outlined),
    title: const Text('ID'),
    subtitle: Text(id),
    trailing: IconButton(
      icon: const Icon(Icons.copy_outlined),
      tooltip: 'Скопировать',
      onPressed: () {
        unawaited(Clipboard.setData(ClipboardData(text: id)));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ID скопирован')));
      },
    ),
    onTap: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Код друга'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: DvQr(data: dvAddLink(id), size: 220, color: Colors.black),
            ),
            const SizedBox(height: 12),
            SelectableText(
              id,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L10n.of(context).close),
          ),
        ],
      ),
    ),
  );
}

/// Переключатель «Уведомлять о днях рождения друзей» (общий, хранится на сервере)
class DvBirthdayNotifyTile extends StatefulWidget {
  const DvBirthdayNotifyTile({super.key});

  @override
  State<DvBirthdayNotifyTile> createState() => _DvBirthdayNotifyTileState();
}

class _DvBirthdayNotifyTileState extends State<DvBirthdayNotifyTile> {
  bool _value = DvProfiles.notifyCached;
  bool _busy = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final client = Matrix.of(context).client;
    final id = client.userID;
    if (id == null) return;
    try {
      await DvProfiles.load(client, [id]);
    } catch (e) {
      Logs().v('DVChat: настройка дней рождения не загружена', e);
    }
    if (mounted) setState(() => _value = DvProfiles.notifyCached);
  }

  Future<void> _toggle(bool value) async {
    final client = Matrix.of(context).client;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _value = value;
      _busy = true;
    });
    try {
      await DvProfiles.saveNotify(client, value: value);
    } catch (e) {
      Logs().v('DVChat: настройка дней рождения не сохранена', e);
      if (mounted) setState(() => _value = !value);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось сохранить настройку. Проверьте соединение.',
          ),
        ),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    secondary: const Icon(Icons.cake_outlined),
    title: const Text('Уведомлять о днях рождения друзей'),
    subtitle: const Text(
      'Напоминание в день рождения тех друзей, кто указал дату',
    ),
    value: _value,
    onChanged: _busy ? null : _toggle,
  );
}

class _BirthdayResult {
  const _BirthdayResult(this.value);

  final DvBirthday? value;
}

/// Окно выбора даты по центру экрана: три барабана (день, месяц, год), год можно не указывать
class _BirthdaySheet extends StatefulWidget {
  const _BirthdaySheet({required this.initial});

  final DvBirthday? initial;

  @override
  State<_BirthdaySheet> createState() => _BirthdaySheetState();
}

class _BirthdaySheetState extends State<_BirthdaySheet> {
  static const int _firstYear = 1920;
  final int _lastYear = DateTime.now().year;

  late int _day;
  late int _month;
  late int _yearIndex;
  late final FixedExtentScrollController _dayController;
  late final FixedExtentScrollController _monthController;
  late final FixedExtentScrollController _yearController;

  int? get _year => _yearIndex == 0 ? null : _lastYear - _yearIndex + 1;

  int get _daysInMonth => DateTime(_year ?? 2000, _month + 1, 0).day;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _day = initial?.day ?? 1;
    _month = initial?.month ?? 1;
    final year = initial?.year;
    _yearIndex = year == null || year > _lastYear || year < _firstYear
        ? 0
        : _lastYear - year + 1;
    _dayController = FixedExtentScrollController(initialItem: _day - 1);
    _monthController = FixedExtentScrollController(initialItem: _month - 1);
    _yearController = FixedExtentScrollController(initialItem: _yearIndex);
  }

  @override
  void dispose() {
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  /// После смены месяца или года день может не существовать (30 февраля)
  void _fixDay() {
    final limit = _daysInMonth;
    if (_day > limit) {
      _day = limit;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_dayController.hasClients) _dayController.jumpToItem(_day - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = TextStyle(
      fontSize: 22,
      color: theme.colorScheme.onSurface,
    );
    Widget wheel(
      FixedExtentScrollController controller,
      List<String> labels,
      ValueChanged<int> onChanged,
    ) => CupertinoPicker(
      scrollController: controller,
      itemExtent: 44,
      onSelectedItemChanged: onChanged,
      children: [
        for (final label in labels)
          Center(child: Text(label, style: textStyle)),
      ],
    );
    final days = [for (var i = 1; i <= _daysInMonth; i++) '$i'];
    final years = [
      'Без года',
      for (var y = _lastYear; y >= _firstYear; y--) '$y',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('День рождения', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Год можно не указывать', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: wheel(
                    _dayController,
                    days,
                    (i) => setState(() => _day = i + 1),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: wheel(_monthController, DvBirthday.monthNames, (i) {
                    setState(() {
                      _month = i + 1;
                      _fixDay();
                    });
                  }),
                ),
                Expanded(
                  flex: 3,
                  child: wheel(_yearController, years, (i) {
                    setState(() {
                      _yearIndex = i;
                      _fixDay();
                    });
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.initial != null)
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(const _BirthdayResult(null)),
                  child: const Text('Убрать'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(L10n.of(context).cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(_BirthdayResult(DvBirthday(_day, _month, _year))),
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

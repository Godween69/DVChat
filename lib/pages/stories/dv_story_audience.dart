// DVChat: выбор, кому показать сторис: всем друзьям или отдельным людям.

import 'package:dvchat/utils/dv_api.dart';
import 'package:dvchat/utils/dv_stories.dart';
import 'package:dvchat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// null значит «отмена»
Future<DvAudience?> pickStoryAudience(BuildContext context, Client client) {
  return showModalBottomSheet<DvAudience>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _AudienceSheet(client: client),
  );
}

class _AudienceSheet extends StatefulWidget {
  final Client client;
  const _AudienceSheet({required this.client});

  @override
  State<_AudienceSheet> createState() => _AudienceSheetState();
}

class _AudienceSheetState extends State<_AudienceSheet> {
  bool _all = true;
  final Set<String> _picked = {};
  late final Future<List<String>> _friends = _load();

  Future<List<String>> _load() async {
    final json = await DvApi(widget.client).get('friends');
    final raw = json['friends'];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, Object?>>()
        .map((m) => m['user_id'])
        .whereType<String>()
        .toList();
  }

  Widget _mode(String title, bool value) => ListTile(
    leading: Icon(
      _all == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
    ),
    title: Text(title),
    onTap: () => setState(() => _all = value),
  );

  @override
  Widget build(BuildContext context) {
    final canPublish = _all || _picked.isNotEmpty;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Кому показать сторис?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          _mode('Всем друзьям', true),
          _mode('Выбрать друзей', false),
          if (!_all)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: FutureBuilder<List<String>>(
                future: _friends,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Не удалось загрузить друзей: ${snapshot.error}',
                      ),
                    );
                  }
                  final list = snapshot.data;
                  if (list == null) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Пока нет друзей'),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final id = list[i];
                      return FutureBuilder<Profile>(
                        initialData: DvStories.profileData[id],
                        future: DvStories.profile(widget.client, id),
                        builder: (context, snap) {
                          final name = DvStories.nameOf(
                            widget.client,
                            id,
                            snap.data,
                          );
                          return CheckboxListTile(
                            value: _picked.contains(id),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _picked.add(id);
                              } else {
                                _picked.remove(id);
                              }
                            }),
                            secondary: Avatar(
                              mxContent: snap.data?.avatarUrl,
                              name: name,
                              client: widget.client,
                              size: 36,
                            ),
                            title: Text(name),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canPublish
                    ? () => Navigator.of(context).pop(
                        _all
                            ? const DvAudience.all()
                            : DvAudience.some(_picked.toList()),
                      )
                    : null,
                child: const Text('Опубликовать'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

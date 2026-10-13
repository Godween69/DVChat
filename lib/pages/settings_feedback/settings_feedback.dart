// DVChat: форма обратной связи. Письмо уходит администратору,
// личный чат с ним появляется у человека после ответа.

import 'package:dvchat/config/themes.dart';
import 'package:dvchat/utils/dv_api.dart';
import 'package:dvchat/widgets/future_loading_dialog.dart';
import 'package:dvchat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class SettingsFeedback extends StatefulWidget {
  const SettingsFeedback({super.key});

  @override
  State<SettingsFeedback> createState() => _SettingsFeedbackState();
}

class _SettingsFeedbackState extends State<SettingsFeedback> {
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  bool get _canSend => _message.text.trim().isNotEmpty;

  Future<void> _send() async {
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => DvApi(client).post('feedback', {
        'subject': _subject.text.trim(),
        'message': _message.text.trim(),
      }),
    );
    if (result.error != null || !mounted) return;
    _subject.clear();
    _message.clear();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Сообщение отправлено. Администратор ответит вам в чате'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: DvThemes.isColumnMode(context)
            ? null
            : Center(
                child: BackButton(
                  onPressed: () => context.go('/rooms/settings'),
                ),
              ),
        title: const Text('Обратная связь'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Напишите администратору: вопрос, идею или сообщение об ошибке. '
            'Ответ придёт вам в личный чат.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _subject,
            maxLength: 100,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Тема',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLength: 2000,
            minLines: 5,
            maxLines: 10,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Сообщение',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _canSend ? _send : null,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Отправить'),
          ),
        ],
      ),
    );
  }
}
